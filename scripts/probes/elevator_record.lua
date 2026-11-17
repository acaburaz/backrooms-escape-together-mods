-- Records what the game's own Level 0 elevator does, from the start of the ride until its doors are
-- open. Loaded through the test console by scripts/record_elevator.py, which replaces __LOG__ with the
-- file to write and __HANDS_OFF__ with true (the mod leaves the ride alone, so this is the real level)
-- or false (the mod takes the ride to its own floor, and this records how that went).
-- Nothing here changes the game.
--
-- One hazard rules how this is written: calling a method on an object that is not valid crashes the
-- game and pcall does not catch it. Every object is checked with valid() first, and only simple
-- property types are read.

local PATH = "__LOG__"
local ELEVATOR = "/Game/Features/Objectives/Levels/Level_0/Elevator/BP_ElevatorFinal.BP_ElevatorFinal_C"
local MANAGER = "/Game/Features/Managers/Levels/Level_0/BP_Level0Manager.BP_Level0Manager_C"
local SECONDS = 150
local HANDS_OFF = __HANDS_OFF__

local R = { run = 0 }
local file = nil
local t0 = os.clock()

local function w(text)
    if file == nil then
        return
    end
    file:write(string.format("%8.2f  %s\n", os.clock() - t0, tostring(text)))
    file:flush()
end

local function valid(o)
    if o == nil or type(o) == "number" or type(o) == "string" or type(o) == "boolean" then
        return false
    end
    local ok, result = pcall(function()
        return o:IsValid()
    end)
    return ok and result == true
end

local function name_of(o)
    if not valid(o) then
        return "nil"
    end
    local ok, text = pcall(function()
        return o:GetFullName()
    end)
    return ok and tostring(text) or "?"
end

local SIMPLE = {
    BoolProperty = true, FloatProperty = true, DoubleProperty = true, IntProperty = true, ByteProperty = true,
    EnumProperty = true, Int64Property = true, UInt32Property = true, Int16Property = true, UInt16Property = true,
}

local function num(v)
    if type(v) == "number" then
        if v == math.floor(v) and math.abs(v) < 1e9 then
            return string.format("%d", v)
        end
        return string.format("%.2f", v)
    end
    return tostring(v)
end

-- The properties of a class or struct that are safe to read, with the fields of the structs among them.
local function props_of(struct, depth)
    local list = {}
    pcall(function()
        struct:ForEachProperty(function(prop)
            local entry = nil
            pcall(function()
                entry = { name = prop:GetFName():ToString(), type = prop:GetClass():GetFName():ToString() }
            end)
            if entry == nil then
                return
            end
            if entry.type == "StructProperty" and depth > 0 then
                pcall(function()
                    local inner = prop:GetStruct()
                    if valid(inner) then
                        entry.struct = inner:GetFName():ToString()
                        entry.fields = props_of(inner, depth - 1)
                    end
                end)
            end
            list[#list + 1] = entry
        end)
    end)
    return list
end

local function read(owner, entry)
    local text = nil
    pcall(function()
        local kind = entry.type
        if SIMPLE[kind] then
            text = num(owner[entry.name])
        elseif kind == "NameProperty" or kind == "StrProperty" then
            text = owner[entry.name]:ToString()
        elseif kind == "ObjectProperty" then
            text = name_of(owner[entry.name])
        elseif kind == "StructProperty" then
            local value = owner[entry.name]
            if entry.fields ~= nil and #entry.fields > 0 then
                local parts = {}
                for _, field in ipairs(entry.fields) do
                    local inner = read(value, field)
                    if inner ~= nil then
                        parts[#parts + 1] = field.name .. "=" .. inner
                    end
                end
                text = "{" .. table.concat(parts, " ") .. "}"
            end
        end
    end)
    return text
end

local function class_chain(object)
    local chain = {}
    pcall(function()
        local class = object:GetClass()
        while valid(class) and #chain < 8 do
            local full = class:GetFullName()
            chain[#chain + 1] = class
            if full:find("/Script/Engine.Actor", 1, true) or full:find("/Script/Engine.ActorComponent", 1, true)
                or full:find("/Script/CoreUObject.Object", 1, true) then
                break
            end
            class = class:GetSuperStruct()
        end
    end)
    return chain
end

-- Everything about the elevator that does not change: classes, properties, functions, components.
local function describe(elevator)
    R.props = {}
    for index, class in ipairs(class_chain(elevator)) do
        local full = name_of(class)
        local engine = full:find("/Script/Engine.", 1, true) ~= nil
        w("CLASS " .. index .. " " .. full)
        if not engine then
            local props = props_of(class, 2)
            local names = {}
            for _, entry in ipairs(props) do
                names[#names + 1] = entry.name .. ":" .. entry.type .. (entry.struct and ("<" .. entry.struct .. ">") or "")
                R.props[#R.props + 1] = entry
            end
            w("  PROPS " .. table.concat(names, ", "))
            local functions = {}
            pcall(function()
                class:ForEachFunction(function(fn)
                    functions[#functions + 1] = fn:GetFName():ToString()
                end)
            end)
            w("  FUNCS " .. table.concat(functions, ", "))
        end
    end
    pcall(function()
        local origin, extent = {}, {}
        elevator:GetActorBounds(false, origin, extent, false)
        w(string.format("BOUNDS centre %.1f %.1f %.1f  half size %.1f %.1f %.1f", origin.X, origin.Y, origin.Z, extent.X, extent.Y, extent.Z))
    end)
    R.parts = {}
    pcall(function()
        local base = StaticFindObject("/Script/Engine.SceneComponent")
        local list = elevator:K2_GetComponentsByClass(base)
        for index = 1, #list do
            local part = list[index]
            if valid(part) then
                local entry = { part = part, name = part:GetFName():ToString(), class = part:GetClass():GetFName():ToString() }
                local rel, world, rot, scale = part.RelativeLocation, part:K2_GetComponentLocation(), part.RelativeRotation, part.RelativeScale3D
                local mesh = ""
                pcall(function()
                    if entry.class:find("StaticMeshComponent", 1, true) and valid(part.StaticMesh) then
                        mesh = " mesh " .. part.StaticMesh:GetFName():ToString()
                    end
                end)
                local parent = ""
                pcall(function()
                    local up = part:GetAttachParent()
                    if valid(up) then
                        parent = " under " .. up:GetFName():ToString()
                    end
                end)
                w(string.format("PART %s (%s)%s rel %.1f %.1f %.1f rot %.1f %.1f %.1f scale %.2f %.2f %.2f world %.1f %.1f %.1f%s", entry.name,
                    entry.class, parent, rel.X, rel.Y, rel.Z, rot.Pitch, rot.Yaw, rot.Roll, scale.X, scale.Y, scale.Z, world.X, world.Y, world.Z, mesh))
                R.parts[#R.parts + 1] = entry
            end
        end
    end)
    w("PARTS " .. #R.parts)
end

local function local_controller()
    for _, controller in ipairs(FindAllOf("PlayerController") or {}) do
        if valid(controller) then
            local mine = false
            pcall(function()
                mine = controller:IsLocalController()
            end)
            if mine then
                return controller
            end
        end
    end
    return nil
end

local function changed(key, text)
    R.last = R.last or {}
    if R.last[key] ~= text then
        local before = R.last[key]
        R.last[key] = text
        return true, before
    end
    return false, nil
end

local function sample(run)
    if run ~= R.run then
        return
    end
    local elevator = nil
    for _, found in ipairs(FindAllOf("BP_ElevatorFinal_C") or {}) do
        if valid(found) then
            elevator = found
        end
    end
    if elevator == nil then
        if changed("elevator", "none") then
            w("NO ELEVATOR")
        end
        return
    end
    if changed("elevator", name_of(elevator)) then
        w("ELEVATOR " .. name_of(elevator))
        describe(elevator)
    end
    R.count = (R.count or 0) + 1
    local at, rot = elevator:K2_GetActorLocation(), elevator:K2_GetActorRotation()
    local where = string.format("%.1f %.1f %.1f yaw %.1f pitch %.1f roll %.1f", at.X, at.Y, at.Z, rot.Yaw, rot.Pitch, rot.Roll)
    if changed("at", where) or R.count % 20 == 0 then
        w("CAR " .. where)
    end
    for _, entry in ipairs(R.props or {}) do
        local text = read(elevator, entry)
        if text ~= nil then
            local diff, before = changed("p." .. entry.name, text)
            if diff then
                w("PROP " .. entry.name .. " = " .. text .. (before and ("   (was " .. before .. ")") or ""))
            end
        end
    end
    for _, entry in ipairs(R.parts or {}) do
        if valid(entry.part) then
            pcall(function()
                local rel, r = entry.part.RelativeLocation, entry.part.RelativeRotation
                local hidden = ""
                pcall(function()
                    hidden = entry.part:IsVisible() and "" or " hidden"
                end)
                local text = string.format("%.1f %.1f %.1f rot %.1f %.1f %.1f%s", rel.X, rel.Y, rel.Z, r.Pitch, r.Yaw, r.Roll, hidden)
                local diff, before = changed("c." .. entry.name, text)
                if diff and before ~= nil then
                    w("MOVE " .. entry.name .. " rel " .. text)
                end
            end)
        end
    end
    pcall(function()
        local g = CBR.H ~= nil and CBR.H.state() or nil
        if g ~= nil and g.arrival ~= nil then
            local a = g.arrival
            local text = a.state .. (a.failed and " FAILED" or "")
            if changed("arrival", text) then
                w(string.format("MOD arrival %s   floor z %.1f, car should stop at %.1f, car is at %.1f", text, g.O.z, a.stopZ, at.Z))
            end
        end
    end)
    pcall(function()
        local d = elevator.ElevatorMovement.CurrentElevatorMoveData
        local text = string.format("distance %.1f duration %.1f start height %.1f start time %.2f", d.MoveDistance, d.MoveDuration, d.MoveStartHeight, d.MoveStartTime)
        if changed("movedata", text) then
            w("MOVE DATA " .. text .. "   moving " .. tostring(elevator.ElevatorMovement:GetIsMoving()))
        end
    end)
    local controller = local_controller()
    if controller ~= nil then
        local pawn = controller.Pawn
        pcall(function()
            local target = controller:GetViewTarget()
            if changed("view", name_of(target)) then
                w("VIEW " .. name_of(target))
            end
        end)
        pcall(function()
            local text = "moveIgnored " .. tostring(controller:IsMoveInputIgnored()) .. " lookIgnored " .. tostring(controller:IsLookInputIgnored())
            if changed("input", text) then
                w("INPUT " .. text)
            end
        end)
        pcall(function()
            local cam, cr = controller.PlayerCameraManager:GetCameraLocation(), controller.PlayerCameraManager:GetCameraRotation()
            local text = string.format("%.0f %.0f %.0f yaw %.0f pitch %.0f", cam.X, cam.Y, cam.Z, cr.Yaw, cr.Pitch)
            if R.count % 10 == 0 and changed("cam", text) then
                w("CAMERA " .. text)
            end
        end)
        if valid(pawn) then
            pcall(function()
                local p = pawn:K2_GetActorLocation()
                local text = string.format("%.0f %.0f %.0f", p.X, p.Y, p.Z)
                if R.count % 10 == 0 and changed("pawn", text) then
                    w(string.format("PAWN %s   relative to car %.0f %.0f %.0f", text, p.X - at.X, p.Y - at.Y, p.Z - at.Z))
                end
            end)
            pcall(function()
                local parent = pawn:GetAttachParentActor()
                if changed("attach", name_of(parent)) then
                    w("PAWN ATTACHED TO " .. name_of(parent))
                end
            end)
            pcall(function()
                local text = "mode " .. tostring(pawn.CharacterMovement.MovementMode) .. " hidden " .. tostring(pawn.bHidden)
                if changed("move", text) then
                    w("PAWN " .. text)
                end
            end)
        end
    end
    pcall(function()
        local playing = {}
        for _, player in ipairs(FindAllOf("LevelSequencePlayer") or {}) do
            if valid(player) and player:IsPlaying() then
                local what = name_of(player)
                pcall(function()
                    what = what .. " <" .. name_of(player:GetSequence()) .. ">"
                end)
                playing[#playing + 1] = what
            end
        end
        table.sort(playing)
        local text = table.concat(playing, " ; ")
        if changed("sequences", text) then
            w("SEQUENCES PLAYING " .. (text == "" and "none" or text))
        end
    end)
end

local HOOKS = {
    ELEVATOR .. ":StartElevator", ELEVATOR .. ":OnAllPlayersJoined", ELEVATOR .. ":StartMatch", ELEVATOR .. ":OnElevatorStop",
    ELEVATOR .. ":OnElevatorFall", ELEVATOR .. ":OnElevatorCrash", ELEVATOR .. ":QueueElevatorCrashEvents",
    ELEVATOR .. ":MoveElevatorDoors", ELEVATOR .. ":OnRep_DoorsOpen", ELEVATOR .. ":EjectDoors", ELEVATOR .. ":StopDoorTimeline",
    ELEVATOR .. ":ToggleLights", ELEVATOR .. ":WaitForDoorsClosedBeforeLeaving", ELEVATOR .. ":Timeline__FinishedFunc",
    ELEVATOR .. ":PlaySound", ELEVATOR .. ":StopSound",
    "/Script/BETGame.ElevatorMovementComponent:QueueElevatorMovement", "/Script/BETGame.ElevatorMovementComponent:StartElevatorMovement",
    "/Script/BETGame.Level0Elevator:QueueElevatorDoorMovement", "/Script/BETGame.Level0Elevator:OnElevatorMoveStart",
    "/Script/BETGame.Level0Elevator:OnElevatorMoveComplete", "/Script/BETGame.Elevator_Base:StartElevator",
}

local function hook_all()
    if R.hooked then
        return
    end
    R.hooked = true
    for _, path in ipairs(HOOKS) do
        local ok, err = pcall(RegisterHook, path, function()
            w("CALL " .. path:match("([^.:]+:[^:]+)$"))
        end)
        w((ok and "hooked " or "no hook ") .. path:match("([^.:]+:[^:]+)$") .. (ok and "" or ("  " .. tostring(err):sub(1, 80))))
    end
end

local function begin()
    R.run = R.run + 1
    local run = R.run
    R.last, R.props, R.parts, R.count = {}, nil, nil, 0
    if file ~= nil then
        file:close()
    end
    file = io.open(PATH, "w")
    t0 = os.clock()
    w("RECORDING run " .. run .. (HANDS_OFF and ". The mod leaves this ride alone." or ". The mod takes this ride to its own floor."))
    pcall(hook_all)
    LoopAsync(100, function()
        if run ~= R.run or os.clock() - t0 > SECONDS then
            ExecuteInGameThread(function()
                if run == R.run then
                    w("END")
                end
            end)
            return true
        end
        ExecuteInGameThread(function()
            local ok, err = pcall(sample, run)
            if not ok and changed("error", tostring(err)) then
                w("SAMPLE ERROR " .. tostring(err))
            end
        end)
        return false
    end)
end

if CBR.elevatorRecorder == nil then
    CBR.elevatorRecorder = R
    NotifyOnNewObject(MANAGER, function()
        if HANDS_OFF then
            -- The mod's own watch starts 200 ms from now. A new watch number makes it let go of this ride.
            CBR.S.watch = CBR.S.watch + 1
            ExecuteWithDelay(100, function()
                ExecuteInGameThread(function()
                    CBR.S.watch = CBR.S.watch + 1
                end)
            end)
        end
        ExecuteWithDelay(150, function()
            ExecuteInGameThread(begin)
        end)
    end)
    out("recorder armed: the next Level 0 start is recorded to " .. PATH)
else
    out("recorder was already armed")
end
