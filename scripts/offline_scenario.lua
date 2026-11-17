-- Plays one level file against the stand-in game from offline_mock.lua and reports what held.
-- Run through scripts/offline_check.py.
local M, hallsSrc, levelSrc, levelName = ...

local R = { checks = {}, logs = {} }
local function check(id, ok, what, detail)
    R.checks[#R.checks + 1] = { id = id, ok = ok and true or false, what = what, detail = detail or "" }
end

local function seen(text)
    for _, shown in ipairs(M.strings) do
        if shown:find(text, 1, true) then
            return true
        end
    end
    return false
end

local level = assert(load(levelSrc, levelName, "t"))()
local H = assert(load(hallsSrc, "halls.lua", "t"))({
    log = function(text) R.logs[#R.logs + 1] = tostring(text) end,
    level = function() return level end,
})
local text = level.text or {}
local function line(key, fallback)
    local value = text[key]
    if type(value) ~= "string" or value == "" then
        return fallback
    end
    -- Only the part before a {placeholder} is fixed.
    return (value:match("^[^{]*"))
end

local function ticks(seconds, each)
    local stopAt = M.clock + seconds
    while M.clock < stopAt do
        M.clock = M.clock + 0.05
        H.tick()
        if each ~= nil and each() then
            return true
        end
    end
    return false
end

local function G()
    return H.state()
end

local function put(lx, ly)
    local g = G()
    M.pawn:K2_SetActorLocation({ X = g.O.x + lx, Y = g.O.y + ly, Z = g.O.z + 110 })
end

local function wait_for(shown, seconds)
    if seen(shown) then
        return true
    end
    return ticks(seconds, function() return seen(shown) end)
end

-- 1. Entry: the floor builds around the player.
local entered = H.enter({})
local g = G()
check("O1", entered == true and g ~= nil and g.built == true, "The floor builds from this level file",
    entered == true and (#g.actors .. " pieces") or ("H.enter returned " .. tostring(entered) .. "; " .. tostring(R.logs[#R.logs])))
if not (entered == true and g ~= nil) then
    R.failures = M.failures
    return R
end

-- 2. Looks: every room gets its theme, and themes the file brings are the ones used.
local missing = {}
local own = 0
for _ in pairs(level.themes or {}) do
    own = own + 1
end
for _, room in ipairs(level.rooms) do
    if own > 0 and g.themes[room.theme] == nil then
        missing[#missing + 1] = room.id .. " " .. tostring(room.theme)
    end
end
check("O2", #missing == 0, "Every room's theme is one the mod can paint", own .. " themes from the file; " .. table.concat(missing, ", "))

-- 2b. A hand-made layout from the Unreal editor: everything in it is built, everything it takes out is hidden.
if type(level.editor) == "table" then
    local editor, made = level.editor, g.editorCount or {}
    local want = { pieces = #(editor.pieces or {}), lights = #(editor.lights or {}), texts = #(editor.texts or {}) }
    local good = made.pieces == want.pieces and made.lights == want.lights and made.texts == want.texts
        and (made.removed or 0) >= #(editor.remove or {})
    check("O13", good, "The hand-made layout is built: its pieces, lamps and texts are added and what it takes out is hidden",
        string.format("%s/%d pieces, %s/%d lamps, %s/%d texts, %s hidden for %d keys", tostring(made.pieces), want.pieces,
            tostring(made.lights), want.lights, tostring(made.texts), want.texts, tostring(made.removed), #(editor.remove or {})))
end

-- 3. Opening lines reach the screen in the level's own words.
local opening = {}
for _, key in ipairs({ "intro1", "intro2", "goal" }) do
    local want = line(key, nil)
    if want ~= nil and not wait_for(want, 30) then
        opening[#opening + 1] = key
    end
end
check("O3", #opening == 0, "The opening lines on screen are the level file's", table.concat(opening, ", "))

-- 4. A walk through every room: each one's description shows when the player steps in.
local silent = {}
for _, room in ipairs(level.rooms) do
    if room.id ~= level.start then
        put(room.x * 800 + 400, room.y * 800 + 400)
        if not wait_for(room.description, 20) then
            silent[#silent + 1] = room.id
        end
    end
end
check("O4", #silent == 0, "Every room shows its description when entered", table.concat(silent, ", "))

-- 5. The hunt: lights go out with the level's line, and a room with a bed is a refuge where the file says so.
g = G()
local start = g.rooms[level.start]
put(start.x * 800 + 400, start.y * 800 + 400)
ticks(1)
g.nextHunt = M.clock
local began = ticks(20, function() return G().hunt ~= nil end)
local huntLine = line("huntStart", "The lights are out")
check("O5", began and wait_for(huntLine, 10), "A hunt starts and announces itself", began and "" or "no hunt started")
local refugeRoom = nil
for id in pairs(g.refuge or {}) do
    refugeRoom = refugeRoom or g.rooms[id]
end
if level.rules.refuge then
    -- The mod notices within a second; the line itself waits its turn behind the lines already queued.
    local hid, told = false, false
    if refugeRoom ~= nil and G().hunt ~= nil then
        put(refugeRoom.x * 800 + 400, refugeRoom.y * 800 + 400)
        hid = ticks(8, function()
            local hunt = G().hunt
            return hunt ~= nil and hunt.hid == true
        end)
        told = hid and wait_for(line("refuge", "It does not come in here"), 40)
    end
    check("O6", hid and told, "During a hunt, a room with a bed counts as a refuge and says so",
        refugeRoom == nil and "no room with a bed" or (not hid and "standing by the bed was not noticed" or (not told and "the refuge line never showed" or "")))
else
    check("O6", next(g.refuge or {}) == nil, "A level without the refuge rule has no refuges", "")
end
local ended = ticks(60, function() return G().hunt == nil end)
check("O7", ended, "The hunt ends by itself", "")

-- 6. The hall, the last room and the loop.
g = G()
local hall = g.hall
put(hall.x0 + 200, hall.yc)
ticks(1)
local inHall = G().zone == "hall"
local white = false
if inHall then
    for _ = 1, 4000 do
        local at = M.pawn:K2_GetActorLocation()
        M.pawn:K2_SetActorLocation({ X = at.X + 30, Y = at.Y, Z = at.Z })
        M.clock = M.clock + 0.05
        H.tick()
        g = G()
        if g == nil then
            break
        end
        if g.loop > 1 then
            break
        end
        white = white or g.hall.white == true
        if g.zone == "epi" then
            -- Stand in the last room until its door opens, then walk on.
            if g.epi.state ~= "open" then
                M.pawn:K2_SetActorLocation(at)
            end
        end
    end
end
g = G()
check("O8", inHall and white, "Walking the hall without looking back reaches the light", inHall and "" or "the hall was not entered")
check("O9", g ~= nil and g.loop == 2 and g.built == true, "The door at the end leads back into a rebuilt floor, loop 2",
    g ~= nil and ("loop " .. tostring(g.loop) .. ", zone " .. tostring(g.zone) .. ", epi " .. tostring(g.epi and g.epi.state)) or "no floor")
local last = {}
for _, key in ipairs({ "hallEnter", "epi1", "epiSign", "loop" }) do
    local want = line(key, nil)
    if want ~= nil and not wait_for(want, 15) then
        last[#last + 1] = key
    end
end
check("O10", #last == 0, "The hall, the last room and the loop speak the level file's lines", table.concat(last, ", "))

-- 7. Nothing in the mod's own Lua failed along the way.
local tickErrors = {}
for _, entry in ipairs(R.logs) do
    if entry:find("Tick error", 1, true) or entry:find("failed", 1, true) then
        tickErrors[#tickErrors + 1] = entry
    end
end
check("O11", #tickErrors == 0, "No tick reported an error", table.concat(tickErrors, " | "))
local swallowed = {}
for _, first in ipairs(M.failures) do
    swallowed[#swallowed + 1] = first
end
check("O12", #swallowed == 0, "No guarded call failed", table.concat(swallowed, " | "))

R.spawned = M.spawned
R.failures = M.failures
return R
