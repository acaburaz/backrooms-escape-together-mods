-- A stand-in for the game, so halls.lua can be run without it.
-- Every engine object is a mock that accepts any call and any field. That means an engine call can
-- never fail here, so every error that does show up is a mistake in the mod's own Lua: a missing
-- field in a level file, a function used before it exists, a nil where a table was expected.
-- What this cannot tell: whether the engine really does what the mod asks of it.

local M = { calls = {}, strings = {}, spawned = 0, failures = {}, logs = {}, clock = 1000.0, watch = {}, pawnMoves = 0 }
local nextId = 0
local mock

local function zero(v)
    if type(v) == "number" then
        return v
    end
    return 0.0
end

local function vec(v)
    v = v or {}
    return { X = zero(v.X), Y = zero(v.Y), Z = zero(v.Z) }
end

local NUMERIC = { X = true, Y = true, Z = true, Pitch = true, Yaw = true, Roll = true, R = true, G = true, B = true, A = true }

local function note(name, method, ...)
    for index = 1, select("#", ...) do
        local arg = select(index, ...)
        if type(arg) == "string" and #arg > 0 then
            M.strings[#M.strings + 1] = arg
            M.calls[#M.calls + 1] = name .. ":" .. method .. " " .. arg
        end
    end
end

-- Every call made on a watched object is kept in order, so a check can ask what the mod did to it.
local function record(object, method, ...)
    local list = M.watch[object]
    if list ~= nil then
        list[#list + 1] = { name = method, args = table.pack(...) }
    end
end

local METHODS = {
    IsValid = function() return true end,
    IsLocalController = function() return true end,
    IsInViewport = function() return true end,
    IsPartial = function() return false end,
    ToString = function(self) return rawget(self, "_name") end,
    GetFullName = function(self) return rawget(self, "_name") .. "#" .. rawget(self, "_id") end,
    GetAddress = function(self) return rawget(self, "_id") end,
    GetFName = function(self) return mock(rawget(self, "_name")) end,
    K2_GetActorLocation = function(self) return vec(rawget(self, "_loc")) end,
    GetCameraLocation = function() return vec(rawget(M.pawn, "_loc")) end,
    GetCameraRotation = function() return { Pitch = 0.0, Yaw = M.yaw or 0.0, Roll = 0.0 } end,
    K2_GetActorRotation = function() return { Pitch = 0.0, Yaw = 0.0, Roll = 0.0 } end,
    GetControlRotation = function() return { Pitch = 0.0, Yaw = M.yaw or 0.0, Roll = 0.0 } end,
    GetVelocity = function() return vec() end,
    K2_SetActorLocation = function(self, location)
        if self == M.pawn then
            M.pawnMoves = M.pawnMoves + 1
        end
        rawset(self, "_loc", vec(location))
        return true
    end,
    GetActorBounds = function(self, _, origin, extent)
        local at = vec(rawget(self, "_loc"))
        origin.X, origin.Y, origin.Z = at.X, at.Y, at.Z
        extent.X, extent.Y, extent.Z = 150.0, 150.0, 150.0
    end,
    SpawnActor = function(self, class, location)
        M.spawned = M.spawned + 1
        local actor = mock("actor")
        rawset(actor, "_loc", vec(location))
        return actor
    end,
    GetWorld = function() return M.world end,
    GetOwner = function(self) return rawget(self, "_owner") or M.pc end,
}

local meta = {}
meta.__index = function(self, key)
    if NUMERIC[key] then
        return 0.0
    end
    local method = METHODS[key]
    if method ~= nil then
        return function(me, ...)
            note(rawget(self, "_name"), key, ...)
            record(self, key, ...)
            return method(self, ...)
        end
    end
    if type(key) == "number" then
        return nil
    end
    local child = mock(tostring(key))
    rawset(self, key, child)
    return child
end
meta.__call = function(self, me, ...)
    note("", rawget(self, "_name"), me, ...)
    record(me, rawget(self, "_name"), ...)
    return mock(rawget(self, "_name") .. "()")
end
meta.__len = function() return 0 end
meta.__pairs = function() return function() return nil end end
meta.__concat = function(a, b)
    return (type(a) == "table" and "mock" or tostring(a)) .. (type(b) == "table" and "mock" or tostring(b))
end
meta.__tostring = function(self) return "mock:" .. rawget(self, "_name") end
meta.__add = function(a, b) return zero(a) + zero(b) end
meta.__sub = function(a, b) return zero(a) - zero(b) end
meta.__mul = function(a, b) return zero(a) * zero(b) end
meta.__div = function(a, b) return zero(a) / (zero(b) == 0 and 1 or zero(b)) end
meta.__unm = function() return 0.0 end
meta.__lt = function(a, b) return zero(a) < zero(b) end
meta.__le = function(a, b) return zero(a) <= zero(b) end

mock = function(name)
    nextId = nextId + 1
    return setmetatable({ _name = name, _id = nextId }, meta)
end

M.mock = mock
M.world = mock("World")
M.pawn = mock("BP_Survivor_Character_C")
rawset(M.pawn, "_loc", vec({ X = 5000, Y = 5000, Z = 300 }))
M.pc = mock("PlayerController")
rawset(M.pc, "Pawn", M.pawn)
rawset(M.world, "GameState", mock("GameState"))
rawset(M.world.GameState, "PlayerArray", { mock("PlayerState") })

-- The game's elevator as it was measured in the game on Level 0: the car hangs at z 24915 and the game
-- queues a ride of -24924 over 27 s. Once the ride is over the game waits 1.5 s and opens the doors in
-- 4.5 s. The world also gets one mesh of the car, one mesh of the old level and one loose actor of the
-- old level, so a check can see which of them the mod switches off.
--   stuck: the car stops halfway and never arrives.   jam: the car arrives and its doors stay shut.
function M.add_car(opts)
    opts = opts or {}
    local car = mock("BP_ElevatorFinal_C")
    local move = mock("ElevatorMovement")
    rawset(move, "CurrentElevatorMoveData", {
        MoveDistance = -24924.0, MoveDuration = 27.0, MoveStartHeight = 24915.0, MoveStartTime = M.clock + 1.5,
        bPlayElevatorAmbience = true,
    })
    rawset(car, "ElevatorMovement", move)
    rawset(car, "CurrentDoorAlpha", 0.0)
    rawset(car, "_loc", vec({ X = 284, Y = 0, Z = 24915 }))
    local carMesh = mock("ElevatorMesh")
    rawset(carMesh, "_owner", car)
    local oldLevel = mock("BP_Level0ChunkManager_C")
    local oldMesh = mock("InstancedStaticMeshComponent")
    rawset(oldMesh, "_owner", oldLevel)
    M.car, M.carMesh, M.oldMesh, M.oldActor = car, carMesh, oldMesh, mock("StaticMeshActor")
    M.carStuck, M.carJam, M.carDone, M.pawnInCar = opts.stuck == true, opts.jam == true, nil, true
    M.watch = { [car] = {}, [carMesh] = {}, [oldMesh] = {}, [M.oldActor] = {} }
    M.step_car()
    return car
end

function M.remove_car()
    M.car, M.carMesh, M.oldMesh, M.oldActor, M.pawnInCar = nil, nil, nil, nil, false
end

-- What the game does to its elevator in one frame. A player standing in the car is carried with it:
-- that is the game moving the player, not the mod, so it does not count as a move.
function M.step_car()
    local car = M.car
    if car == nil then
        return
    end
    local data = rawget(rawget(car, "ElevatorMovement"), "CurrentElevatorMoveData")
    local alpha = math.max(0, math.min(1, (M.clock - data.MoveStartTime) / data.MoveDuration))
    if M.carStuck then
        alpha = math.min(alpha, 0.5)
    end
    local at = rawget(car, "_loc")
    at.Z = data.MoveStartHeight + data.MoveDistance * (alpha * alpha * (3 - 2 * alpha))
    if alpha >= 1 then
        M.carDone = M.carDone or M.clock
        if not M.carJam then
            rawset(car, "CurrentDoorAlpha", math.max(0, math.min(1, (M.clock - M.carDone - 1.5) / 4.5)))
        end
    end
    if M.pawnInCar then
        -- Where a player stands in the car, as measured: 338 behind the car's origin, 109.2 above it.
        rawset(M.pawn, "_loc", vec({ X = at.X - 338, Y = at.Y - 51, Z = at.Z + 109.2 }))
    end
    -- The old level's loose actor lies where the floor is being built.
    rawset(M.oldActor, "_loc", vec({ X = at.X + 1500, Y = at.Y + 1500, Z = data.MoveStartHeight + data.MoveDistance + 100 }))
end

local found = {}
function FindAllOf(class)
    if class == "PlayerController" then
        return { M.pc }
    elseif class == "BP_Survivor_Character_C" then
        return { M.pawn }
    elseif M.car ~= nil then
        if class == "BP_ElevatorFinal_C" then
            return { M.car }
        elseif class == "StaticMeshComponent" then
            return { M.carMesh, M.oldMesh }
        elseif class == "Actor" then
            return { M.car, M.oldActor }
        end
    end
    return {}
end

function FindFirstOf(class)
    if class == "PlayerController" then
        return M.pc
    elseif class == "World" then
        return M.world
    end
    found[class] = found[class] or mock(class)
    return found[class]
end

function StaticFindObject(path)
    found[path] = found[path] or mock(path)
    return found[path]
end

function StaticConstructObject(class)
    return mock("constructed")
end

function LoadAsset() end
function FName(text) return text end
function FText(text) return text end
function ExecuteInGameThread(fn) fn() end
function ExecuteWithDelay(ms, fn) end
function LoopAsync() end

-- The same run every time.
math.randomseed(1360)

-- The mod keeps time with os.clock. Here the test moves the clock.
os.clock = function() return M.clock end

-- An engine call cannot fail against a mock, so a failed pcall is a mistake in the mod's Lua.
local real_pcall = pcall
pcall = function(fn, ...)
    local function trace(err)
        return debug.traceback(tostring(err), 2)
    end
    local results = table.pack(xpcall(fn, trace, ...))
    if not results[1] then
        local text = tostring(results[2])
        local first = text:match("^[^\n]*")
        if not M.failures[first] then
            M.failures[first] = text
            M.failures[#M.failures + 1] = first
        end
        results[2] = first
    end
    return table.unpack(results, 1, results.n)
end

-- Reading a global that does not exist is how a function used before it is defined shows up.
setmetatable(_G, {
    __index = function(_, key)
        error("read of undefined global '" .. tostring(key) .. "'", 2)
    end,
})

return M
