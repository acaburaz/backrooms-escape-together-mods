-- A stand-in for the game, so halls.lua can be run without it.
-- Every engine object is a mock that accepts any call and any field. That means an engine call can
-- never fail here, so every error that does show up is a mistake in the mod's own Lua: a missing
-- field in a level file, a function used before it exists, a nil where a table was expected.
-- What this cannot tell: whether the engine really does what the mod asks of it.

local M = { calls = {}, strings = {}, spawned = 0, failures = {}, logs = {}, clock = 1000.0 }
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
        rawset(self, "_loc", vec(location))
        return true
    end,
    SpawnActor = function(self, class, location)
        M.spawned = M.spawned + 1
        local actor = mock("actor")
        rawset(actor, "_loc", vec(location))
        return actor
    end,
    GetWorld = function() return M.world end,
    GetOwner = function() return M.pc end,
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

local found = {}
function FindAllOf(class)
    if class == "PlayerController" then
        return { M.pc }
    elseif class == "BP_Survivor_Character_C" then
        return { M.pawn }
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
