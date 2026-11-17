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
-- A copy of the mod with its own floor. The run uses one; the last checks start a few more.
local function mod_for(levelTable)
    return assert(load(hallsSrc, "halls.lua", "t"))({
        log = function(text) R.logs[#R.logs + 1] = tostring(text) end,
        level = function() return levelTable end,
    })
end
local H = mod_for(level)
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
        M.step_car()
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

-- What was measured on the game's own elevator (AGENTS.md, "The elevator"): the car floor is 12 above
-- the car's origin, the clear doorway is 131 wide and 230 high and sits 3.75 to one side of the origin,
-- and the door plane is just in front of the origin.
local CAR_FLOOR, CAR_DOOR_Y, CAR_DOOR_W, CAR_DOOR_H, FLOOR_DROP = 12, -3.75, 131, 230, 2400

local function called(object, method, test)
    for index, call in ipairs(M.watch[object] or {}) do
        if call.name == method and (test == nil or test(call.args)) then
            return index
        end
    end
    return nil
end

-- What the mod must never do to the car that brings the players.
local function car_harm(car)
    local harm = {}
    if called(car, "SetActorTickEnabled", function(args) return args[1] == false end) then
        harm[#harm + 1] = "its tick was switched off"
    end
    if called(car, "SetActorHiddenInGame", function(args) return args[1] == true end) then
        harm[#harm + 1] = "it was hidden"
    end
    if called(car, "SetActorEnableCollision", function(args) return args[1] == false end) then
        harm[#harm + 1] = "its collision was switched off"
    end
    for _, method in ipairs({ "SetActorScale3D", "K2_SetActorLocation", "K2_DestroyActor", "QueueElevatorMovement",
        "StartElevatorMovement", "QueueElevatorDoorMovement", "MoveElevatorDoors" }) do
        if called(car, method) then
            harm[#harm + 1] = method .. " was called on it"
        end
    end
    return harm
end

local function start_room()
    for _, room in ipairs(level.rooms) do
        if room.id == level.start then
            return room
        end
    end
end

-- 0. Before the game has queued the elevator's ride there is nothing to line the floor up with.
local early = H.enter({})
check("O17", early == false and G() == nil, "Nothing is built before the game has queued the elevator's ride",
    "H.enter returned " .. tostring(early))

-- 1. Entry: the floor builds where the game's elevator is told to stop.
local car = M.add_car()
local moveData = car.ElevatorMovement.CurrentElevatorMoveData
local movesAtStart = M.pawnMoves
local entered = H.enter({ record = true })
local g = G()
check("O1", entered == true and g ~= nil and g.built == true, "The floor builds from this level file",
    entered == true and (#g.actors .. " pieces") or ("H.enter returned " .. tostring(entered) .. "; " .. tostring(R.logs[#R.logs])))
if not (entered == true and g ~= nil) then
    R.failures = M.failures
    return R
end

-- 1b. The ride is the game's own, only shorter, and the floor meets the car where it stops.
do
    local notes = {}
    local startRoom = start_room()
    local stopZ = moveData.MoveStartHeight + moveData.MoveDistance
    if moveData.MoveDistance ~= -FLOOR_DROP then
        notes[#notes + 1] = "the ride is " .. tostring(moveData.MoveDistance) .. " long, not " .. -FLOOR_DROP
    end
    if moveData.MoveDuration ~= 27.0 then
        notes[#notes + 1] = "the ride's duration was changed to " .. tostring(moveData.MoveDuration)
    end
    if g.arrival == nil or g.arrival.state ~= "riding" or math.abs(g.arrival.stopZ - stopZ) > 0.01 then
        notes[#notes + 1] = "the mod is not waiting for the car at z " .. stopZ
    end
    if math.abs(g.O.z - (stopZ + CAR_FLOOR)) > 0.01 then
        notes[#notes + 1] = string.format("the floor is at z %.2f, the car floor will be at %.2f", g.O.z, stopZ + CAR_FLOOR)
    end
    local carAt = car:K2_GetActorLocation()
    local wallX = g.O.x + startRoom.x * 800
    if wallX < carAt.X or wallX - carAt.X > 10 then
        notes[#notes + 1] = string.format("the wall's outer face is %.1f in front of the car's origin", wallX - carAt.X)
    end
    local doorY = startRoom.y * 800 + 400
    if math.abs((g.O.y + doorY) - (carAt.Y + CAR_DOOR_Y)) > 0.01 then
        notes[#notes + 1] = string.format("the doorway is centred %.2f off the car's doors", (g.O.y + doorY) - (carAt.Y + CAR_DOOR_Y))
    end
    -- Nothing solid may stand in the opening the car's doors leave: no wall, no landing doors, no mat.
    local x0, x1 = startRoom.x * 800 - 1, startRoom.x * 800 + 40
    for _, piece in ipairs(g.record or {}) do
        if piece.type == "piece" and not piece.ghost then
            local at, size = piece.at, piece.size
            if at[1] + size[1] / 2 > x0 and at[1] - size[1] / 2 < x1
                and at[2] + size[2] / 2 > doorY - CAR_DOOR_W / 2 and at[2] - size[2] / 2 < doorY + CAR_DOOR_W / 2
                and at[3] + size[3] / 2 > 1 and at[3] - size[3] / 2 < CAR_DOOR_H - 1 then
                notes[#notes + 1] = "in the doorway: " .. piece.key
            end
        end
    end
    if g.carDoors ~= nil then
        notes[#notes + 1] = "the landing doors are shut in front of the car"
    end
    check("O18", #notes == 0,
        "The game's ride is shortened to stop at the floor; the floor is level with the car floor and its doorway is open in front of the car's doors",
        #notes == 0 and string.format("ride %d over %d s, floor z %.1f", moveData.MoveDistance, moveData.MoveDuration, g.O.z)
            or table.concat(notes, "; "))
end

-- 1c. The ride. The mod only watches: it says nothing and runs nothing on the floor until the car has
-- stopped, and starts the floor when the game opens the doors.
do
    local notes = {}
    local function note(text)
        for _, have in ipairs(notes) do
            if have == text then
                return
            end
        end
        notes[#notes + 1] = text
    end
    local intro1, intro2 = line("intro1", "The elevator stopped between floors"), line("intro2", "The doors opened anyway")
    local rodeFrom, stoppedAt, openAt, sawState = M.clock, nil, nil, {}
    local huntAtBuild = G().nextHunt
    ticks(60, function()
        local gg = G()
        local a = gg.arrival
        sawState[a.state] = true
        if a.state == "riding" then
            -- main.lua asks for this whenever the game makes a new elevator object. It must not touch
            -- a car that is on its way to the floor.
            H.stop_elevator_ride()
            if seen(intro1) or seen(intro2) then
                note("an opening line showed while the car was still moving")
            end
            if gg.zone ~= "car" or gg.hunt ~= nil or gg.nextHunt ~= huntAtBuild then
                note("the floor was already running during the ride")
            end
        elseif a.state == "stopped" then
            stoppedAt = stoppedAt or M.clock
            if seen(intro2) then
                note("the doors line showed before the doors moved")
            end
            if gg.zone ~= "car" or gg.nextHunt ~= huntAtBuild then
                note("the floor started before the doors moved")
            end
        elseif a.state == "open" or a.state == "done" then
            openAt = openAt or M.clock
        end
        return a.state == "done"
    end)
    local gg = G()
    local stopZ = moveData.MoveStartHeight + moveData.MoveDistance
    if not (sawState.riding and sawState.stopped and sawState.open and gg.arrival.state == "done") then
        note("the arrival ended as '" .. tostring(gg.arrival.state) .. "'")
    end
    if gg.arrival.failed then
        note("the mod gave up on the car")
    end
    if math.abs(car:K2_GetActorLocation().Z - stopZ) > 0.01 or car.CurrentDoorAlpha < 0.99 then
        note("the car is not at the floor with its doors open")
    end
    if not wait_for(intro1, 10) or not wait_for(intro2, 20) then
        note("the opening lines did not follow the stop and the doors")
    end
    if openAt ~= nil and (gg.builtAt ~= openAt or gg.nextHunt == huntAtBuild) then
        note("the floor's clocks did not start when the doors opened")
    end
    check("O19", #notes == 0, "During the ride the floor waits and nothing is said; the mod speaks when the car stops and starts the floor when its doors open",
        #notes == 0 and string.format("stopped after %.1f s, doors after %.1f s", stoppedAt - rodeFrom, openAt - rodeFrom) or table.concat(notes, "; "))

    -- 1d. Hands off: the game carries the player and works the car.
    local harm = car_harm(car)
    if M.pawnMoves ~= movesAtStart then
        harm[#harm + 1] = "a player was moved " .. (M.pawnMoves - movesAtStart) .. " times"
    end
    if called(M.carMesh, "SetHiddenInGame") or called(M.carMesh, "SetVisibility")
        or called(M.carMesh, "SetWorldScale3D") or called(M.carMesh, "SetCollisionEnabled") then
        harm[#harm + 1] = "the car's mesh was switched off"
    end
    if gg.carDoors ~= nil then
        harm[#harm + 1] = "landing doors were put in front of the open car"
    end
    local hidden, solidOff, shrunk = called(M.oldMesh, "SetHiddenInGame"), called(M.oldMesh, "SetCollisionEnabled"),
        called(M.oldMesh, "SetWorldScale3D")
    if not (hidden and solidOff and shrunk) then
        harm[#harm + 1] = "the old level's mesh was not switched off"
    elseif solidOff > shrunk then
        harm[#harm + 1] = "the old level's mesh was shrunk while still solid (that froze the game for seconds)"
    end
    if not called(M.oldActor, "SetActorHiddenInGame", function(args) return args[1] == true end) then
        harm[#harm + 1] = "the old level's actor on the floor was not hidden"
    end
    check("O20", #harm == 0,
        "The mod moves no player and leaves the car alone: not hidden, not stopped, not made untouchable; only the old level is switched off, collision first",
        table.concat(harm, "; "))

    -- The player walks out of the car into the first room.
    M.pawnInCar = false
    local startRoom = start_room()
    put(startRoom.x * 800 + 400, startRoom.y * 800 + 400)
    ticks(1)
    check("O21", G().zone == "room" and G().roomId == level.start, "Walking out of the car puts the player in the first room",
        "zone " .. tostring(G().zone) .. ", room " .. tostring(G().roomId))
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

-- 4b. Walking the rooms over and over never moves the player anywhere: the mod has no hunger or
-- tiredness of its own to pass out from. Sanity and stamina are the game's.
local function moved_from(lx, ly)
    local gg, at = G(), M.pawn:K2_GetActorLocation()
    if math.abs(at.X - (gg.O.x + lx)) > 1 or math.abs(at.Y - (gg.O.y + ly)) > 1 then
        return string.format("put at %d %d, found at %d %d", lx, ly, at.X - gg.O.x, at.Y - gg.O.y)
    end
    return nil
end
local carried = {}
for round = 1, 3 do
    for _, room in ipairs(level.rooms) do
        local lx, ly = room.x * 800 + 400, room.y * 800 + 400
        put(lx, ly)
        ticks(2)
        local where = moved_from(lx, ly)
        if where ~= nil then
            carried[#carried + 1] = "round " .. round .. " " .. room.id .. ": " .. where
        end
    end
end
check("O14", #carried == 0, "Walking through every room three times over never moves the player", table.concat(carried, "; "))
g = G()
check("O15", g.hunger == nil and g.stamina == nil and not seen("HUNGER") and not seen("STAMINA")
    and not seen("F9 rests") and not seen("Eat. Rest."),
    "The mod keeps and shows no hunger or stamina of its own, and tells nobody to eat or rest with F9",
    "hunger " .. tostring(g.hunger) .. ", stamina " .. tostring(g.stamina) .. (seen("HUNGER") and ", HUNGER on screen" or "")
        .. ((seen("F9 rests") or seen("Eat. Rest.")) and ", an opening line still says F9 rests" or ""))

-- 4c. The dead-end passage: walking to its end moves nobody. It closes once the player is back out and
-- looking the other way, and says so when the player looks again.
local fake = g.fake
local fakeNote = {}
local endX = -700
put(endX, fake.yc)
ticks(3)
if G().fake.state ~= "seen" then
    fakeNote[#fakeNote + 1] = "reaching the end left the passage '" .. tostring(G().fake.state) .. "'"
end
local carriedOut = moved_from(endX, fake.yc)
if carriedOut ~= nil then
    fakeNote[#fakeNote + 1] = "the player was moved: " .. carriedOut
end
local roomX, roomY = fake.room.x * 800 + 400, fake.room.y * 800 + 400
M.yaw = 180.0
put(roomX, roomY)
ticks(2)
if G().fake.state ~= "seen" then
    fakeNote[#fakeNote + 1] = "it closed while the player was looking at it"
end
M.yaw = 0.0
ticks(2)
if G().fake.state ~= "sealed" then
    fakeNote[#fakeNote + 1] = "it did not close behind the player's back ('" .. tostring(G().fake.state) .. "')"
end
M.yaw = 180.0
local told = wait_for(line("noDoor", "There was never a door there"), 40)
if not told or G().fake.state ~= "gone" then
    fakeNote[#fakeNote + 1] = "looking again did not bring the line"
end
if moved_from(roomX, roomY) ~= nil then
    fakeNote[#fakeNote + 1] = "the player was moved out of the room"
end
M.yaw = 0.0
check("O16", #fakeNote == 0, "The dead-end passage closes behind the player's back and moves nobody", table.concat(fakeNote, "; "))

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

-- 7. When the car cannot bring the players, the old way in still works: landing doors shut, players
-- put in the first room. Each case gets a copy of the mod of its own.
do
    local function in_start_room(mod)
        local gg = mod.state()
        local room, at = start_room(), M.pawn:K2_GetActorLocation()
        return gg ~= nil and math.abs(at.X - (gg.O.x + room.x * 800 + 400)) < 1 and math.abs(at.Y - (gg.O.y + room.y * 800 + 400)) < 1
    end
    local function run(mod, seconds, done)
        local stopAt = M.clock + seconds
        while M.clock < stopAt do
            M.clock = M.clock + 0.05
            M.step_car()
            mod.tick()
            if done() then
                return true
            end
        end
        return false
    end
    local notes = {}

    -- No elevator in the world at all.
    M.remove_car()
    local none = mod_for(level)
    if none.enter({}) ~= false then
        notes[#notes + 1] = "without a car the floor was built before the fallback asked for it"
    end
    M.pawn:K2_SetActorLocation({ X = 5000, Y = 5000, Z = 300 })
    if none.enter({ cut = true }) ~= true or none.state().arrival ~= nil or none.state().carDoors == nil or not in_start_room(none) then
        notes[#notes + 1] = "without a car: the players were not put in the first room behind shut landing doors"
    end

    -- A car that stops halfway, and a car whose doors stay shut.
    for _, case in ipairs({ { "stuck", 80 }, { "jam", 70 } }) do
        M.add_car({ [case[1]] = true })
        local mod = mod_for(level)
        local ok = mod.enter({}) == true
        local gaveUp = ok and run(mod, case[2], function()
            return mod.state().arrival.failed == true
        end)
        -- From here the player stands where the mod put them, not in the car.
        M.pawnInCar = false
        run(mod, 1, function() return false end)
        if not (ok and gaveUp and mod.state().carDoors ~= nil and in_start_room(mod) and mod.state().zone == "room") then
            notes[#notes + 1] = "a car that is " .. case[1] .. ": the mod did not give up and start in the room ("
                .. tostring(ok and mod.state().arrival.state) .. ")"
        end
        M.remove_car()
    end

    -- A first room with another room where the car would stand.
    local other = nil
    for _, room in ipairs(level.rooms) do
        if room.x > 0 and room.id ~= level.exit.room then
            other = other or room
        end
    end
    if other ~= nil then
        local moved = setmetatable({ start = other.id }, { __index = level })
        local blockedCar = M.add_car()
        local data = blockedCar.ElevatorMovement.CurrentElevatorMoveData
        local mod = mod_for(moved)
        local waited = mod.enter({})
        local built = mod.enter({ cut = true })
        if waited ~= false or built ~= true or data.MoveDistance ~= -24924.0 or mod.state().arrival ~= nil then
            notes[#notes + 1] = "a first room with no free wall for the car: the ride was changed or the floor did not use the old way in"
        end
        M.remove_car()
    end
    check("O22", #notes == 0,
        "With no car, a car that never arrives, doors that stay shut, or no free wall for the car, the players start in the first room behind shut landing doors",
        table.concat(notes, "; "))

    -- Co-op: another player's copy of the mod is told where the host's floor is and that the car goes there.
    local clientCar = M.add_car()
    local data = clientCar.ElevatorMovement.CurrentElevatorMoveData
    local client = mod_for(level)
    local host = G()
    local before = M.pawnMoves
    client.message(string.format("[CBR] BUILD %.3f %.3f %.3f car", host.O.x, host.O.y, host.O.z))
    local cg = client.state()
    local same = cg ~= nil and cg.built == true and cg.host == false and cg.O.x == host.O.x and cg.O.y == host.O.y and cg.O.z == host.O.z
    local rides = same and cg.arrival ~= nil and cg.arrival.state == "riding" and data.MoveDistance == -FLOOR_DROP
        and M.pawnMoves == before and #car_harm(clientCar) == 0
    check("O23", same and rides, "A second player's mod builds the host's floor at the same place and lets its own car ride there",
        not same and "the floor was not built where the host said" or (not rides and ("arrival " .. tostring(cg.arrival and cg.arrival.state)
            .. ", ride " .. tostring(data.MoveDistance) .. ", moved " .. (M.pawnMoves - before)) or ""))
    M.remove_car()
end

-- 8. Nothing in the mod's own Lua failed along the way.
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
