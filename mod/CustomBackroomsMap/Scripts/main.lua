-- CBR_MAP_PICKER_V1
-- Starting Level 0 from the journey list builds the generated floor around the elevator.
-- F9 (key 120) tries the exit door. No travel or cheat commands.
-- The floor itself lives in halls.lua so it can be reloaded while the game runs.

local MOD = "CustomBackroomsMap"
local MARKER = "CBR_MAP_PICKER_V1"
-- The floor to build. levels\active.txt can name another file in that folder.
local LEVEL_FILE = "the_yellow_static.lua"
local PICKER_NAMES = {
    "BPW_JourneyEntry",
    "BPW_JourneyLevelInfo",
    "W_Lobby",
    "WBP_MultiplayerLobbyView",
    "WBP_CreateGameOnboarding",
    "WBP_SelectMultiplayerOptions",
}
local LEVEL0_MANAGER = "/Game/Features/Managers/Levels/Level_0/BP_Level0Manager.BP_Level0Manager_C"
local ELEVATOR = "/Game/Features/Objectives/Levels/Level_0/Elevator/BP_ElevatorFinal.BP_ElevatorFinal_C"

local S = { level = nil, pickerSeen = false, entered = false, watch = 0 }
local H = nil

local function log(text)
    print("[CBR] " .. tostring(text) .. "\n")
end

local function mod_dirs()
    local dirs = {}
    pcall(function()
        local root = IterateGameDirectories().Game.Binaries.Win64.__absolute_path
        dirs[#dirs + 1] = root .. "\\ue4ss\\Mods\\" .. MOD
        dirs[#dirs + 1] = root .. "\\Mods\\" .. MOD
    end)
    dirs[#dirs + 1] = "ue4ss/Mods/" .. MOD
    dirs[#dirs + 1] = "Mods/" .. MOD
    return dirs
end

local function read_mod_file(relative)
    for _, dir in ipairs(mod_dirs()) do
        local path = dir .. relative
        local file = io.open(path, "r")
        if file ~= nil then
            local text = file:read("*a")
            file:close()
            return text, path
        end
    end
    return nil, nil
end

local function flag(name)
    local text = read_mod_file("\\dev\\" .. name .. ".flag")
    return text ~= nil
end

local function load_level()
    local file = LEVEL_FILE
    local picked = read_mod_file("\\levels\\active.txt")
    if picked ~= nil then
        picked = picked:match("([%w_%-]+%.lua)")
        if picked ~= nil then
            file = picked
        end
    end
    local text, path = read_mod_file("\\levels\\" .. file)
    if text == nil and file ~= LEVEL_FILE then
        log("levels\\active.txt names " .. file .. ", which is not there. Using " .. LEVEL_FILE .. ".")
        file = LEVEL_FILE
        text, path = read_mod_file("\\levels\\" .. file)
    end
    if text == nil then
        log("No level file. Expected " .. file .. " beside this mod.")
        return false
    end
    local chunk, err = load(text, path, "t")
    if chunk == nil then
        log("Level parse failed: " .. tostring(err))
        return false
    end
    local ok, level = pcall(chunk)
    if not ok or type(level) ~= "table" then
        log("Level file failed: " .. tostring(level))
        return false
    end
    S.level = level
    log("Loaded " .. tostring(level.pickerLabel) .. " from " .. path)
    -- What was placed by hand in the Unreal editor lives beside the level, so making the level again keeps it.
    local editorFile = file:gsub("%.lua$", ".editor.lua")
    local editorText, editorPath = read_mod_file("\\levels\\" .. editorFile)
    if editorText ~= nil then
        local editorChunk, editorErr = load(editorText, editorPath, "t")
        local good, editor = false, nil
        if editorChunk ~= nil then
            good, editor = pcall(editorChunk)
        end
        if good and type(editor) == "table" then
            level.editor = editor
            log("Loaded hand-made layout from " .. editorPath)
        else
            log("Hand-made layout " .. editorFile .. " failed: " .. tostring(editorErr or editor))
        end
    end
    return true
end

local function load_halls()
    local text, path = read_mod_file("\\Scripts\\halls.lua")
    if text == nil then
        log("halls.lua is missing beside main.lua")
        return false
    end
    local chunk, err = load(text, path, "t")
    if chunk == nil then
        log("halls.lua did not parse: " .. tostring(err))
        return false
    end
    local ok, result = pcall(chunk, {
        log = log,
        level = function()
            return S.level
        end,
    })
    if not ok or type(result) ~= "table" then
        log("halls.lua failed: " .. tostring(result))
        return false
    end
    H = result
    return true
end

-- Delayed and looping callbacks run off the game thread, so hop back before touching the game.
local function later(ms, fn)
    ExecuteWithDelay(ms, function()
        ExecuteInGameThread(fn)
    end)
end

local function first_survivor()
    local list = FindAllOf("BP_Survivor_Character_C")
    if list ~= nil and #list > 0 then
        return list[1]
    end
    return nil
end

-- The intro rides the game's elevator. As soon as the game has queued that ride, the floor is built
-- where the car will stop and the car is told to stop there; the game does the rest. Only when that
-- cannot be done is the ride cut short the old way, once the car has been moving for three seconds.
local function watch_elevator(id)
    if id ~= S.watch or S.entered or H == nil then
        return
    end
    local ok, result = pcall(H.enter, { god = flag("godmode") })
    if ok and result then
        S.entered = true
        log("Elevator rides to " .. tostring(S.level and S.level.pickerLabel))
        return
    end
    if not ok then
        log("Could not build yet: " .. tostring(result))
    end
    local z = nil
    local pawn = first_survivor()
    if pawn ~= nil then
        pcall(function()
            z = pawn:K2_GetActorLocation().Z
        end)
    end
    if z == nil then
        later(200, function()
            watch_elevator(id)
        end)
        return
    end
    local now = os.clock()
    if S.startZ == nil then
        S.startZ = z
        S.watchBegan = now
    end
    if math.abs(z - S.startZ) > 250 and S.movingSince == nil then
        S.movingSince = now
        log("Elevator is moving")
    end
    local movingFor = S.movingSince and (now - S.movingSince) or 0
    if movingFor > 3 or now - S.watchBegan > 25 then
        ok, result = pcall(H.enter, { god = flag("godmode"), cut = true })
        if ok and result then
            S.entered = true
            log("Elevator stops at " .. tostring(S.level and S.level.pickerLabel))
            return
        end
        log("Could not build yet: " .. tostring(result))
    end
    later(200, function()
        watch_elevator(id)
    end)
end

local function on_level0()
    S.watch = S.watch + 1
    S.entered = false
    S.startZ = nil
    S.movingSince = nil
    if H ~= nil then
        pcall(H.forget)
    end
    local id = S.watch
    later(200, function()
        watch_elevator(id)
    end)
end

local function widget_is_picker(fullName)
    for _, name in ipairs(PICKER_NAMES) do
        if fullName:find(name, 1, true) then
            return true
        end
    end
    return false
end

NotifyOnNewObject("/Script/UMG.UserWidget", function(widget)
    if S.pickerSeen then
        return
    end
    local fullName = ""
    pcall(function()
        fullName = widget:GetFullName()
    end)
    if widget_is_picker(fullName) then
        S.pickerSeen = true
        log(MARKER .. " journey list is open. Start Level 0. F9 uses what is in front of you.")
    end
end)

NotifyOnNewObject(LEVEL0_MANAGER, on_level0)

NotifyOnNewObject(ELEVATOR, function()
    if S.entered and H ~= nil then
        pcall(H.stop_elevator_ride)
    end
end)

pcall(function()
    RegisterHook("/Script/Engine.PlayerController:ClientMessage", function(_, message)
        local text = message
        if type(message) ~= "string" then
            pcall(function()
                text = message:get()
            end)
        end
        text = tostring(text or "")
        if H ~= nil and text:find("[CBR] ", 1, true) then
            pcall(H.message, text)
        end
    end)
end)

RegisterKeyBind(120, function()
    ExecuteInGameThread(function()
        if H ~= nil then
            local ok, err = pcall(H.use)
            if not ok then
                log("Use failed: " .. tostring(err))
            end
        end
    end)
end)

LoopAsync(50, function()
    -- A queued tick can get lost on the way to the game thread, so one that is overdue is queued again.
    local now = os.clock()
    if H ~= nil and (not S.tickQueued or now - S.tickQueued > 1) then
        S.tickQueued = now
        ExecuteInGameThread(function()
            S.tickQueued = false
            local ok, err = pcall(H.tick)
            if not ok and err ~= S.lastTickError then
                S.lastTickError = err
                log("Tick failed: " .. tostring(err))
            end
        end)
    end
    return false
end)

-- Test console. Only answers while dev\enabled.flag exists in the installed mod folder.
-- dev\godmode.flag makes the next run start in test godmode.
CBR = { S = S, log = log }

function CBR.reload(opts)
    opts = opts or {}
    local state = H ~= nil and H.state() or nil
    local origin = opts.origin or (state and state.O)
    if opts.god == nil then
        opts.god = (state and state.god) or flag("godmode")
    end
    if H ~= nil then
        pcall(H.teardown)
    end
    if not load_halls() then
        return false
    end
    CBR.H = H
    if origin == nil then
        return true
    end
    return H.build(origin, opts)
end

local function dev_poll()
    if not flag("enabled") then
        return
    end
    local text = read_mod_file("\\dev\\live.lua")
    if text == nil or text == "" or text == S.devLast then
        return
    end
    S.devLast = text
    local _, flagPath = read_mod_file("\\dev\\enabled.flag")
    local outPath = flagPath:gsub("enabled%.flag$", "live.out")
    local id = text:match("^%-%- id: ([^\r\n]+)") or "?"
    ExecuteInGameThread(function()
        local lines = {}
        local env = setmetatable({
            out = function(...)
                local parts = {}
                for index = 1, select("#", ...) do
                    parts[#parts + 1] = tostring((select(index, ...)))
                end
                lines[#lines + 1] = table.concat(parts, "\t")
            end,
        }, {
            __index = function(_, key)
                if key == "H" then
                    return H
                end
                return _G[key]
            end,
        })
        local chunk, err = load(text, "live", "t", env)
        local ok, result = false, err
        if chunk ~= nil then
            ok, result = pcall(chunk)
        end
        local outFile = io.open(outPath, "w")
        if outFile ~= nil then
            outFile:write("id: " .. id .. "\n")
            outFile:write("ok: " .. tostring(ok) .. "\n")
            outFile:write("result: " .. tostring(result) .. "\n")
            outFile:write(table.concat(lines, "\n"))
            outFile:write("\n")
            outFile:close()
        end
    end)
end

LoopAsync(300, function()
    pcall(dev_poll)
    return false
end)

load_level()
load_halls()
CBR.H = H
log(MARKER .. " ready. Starting Level 0 builds " .. ((S.level and S.level.pickerLabel) or "the custom map") .. " with the Skin Stealer.")
