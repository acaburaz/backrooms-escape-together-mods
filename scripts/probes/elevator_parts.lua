-- Lists the parts of the game's Level 0 elevator and the state of its movement component.
-- Run with: python scripts/live.py scripts/probes/elevator_parts.lua   (the game must be on Level 0)
-- Reads only; nothing here changes the game.

local function valid(o)
    if o == nil or type(o) ~= "userdata" then
        return false
    end
    local ok, result = pcall(function()
        return o:IsValid()
    end)
    return ok and result == true
end

local SIMPLE = {
    BoolProperty = true, FloatProperty = true, DoubleProperty = true, IntProperty = true, ByteProperty = true,
    EnumProperty = true, Int64Property = true, UInt32Property = true,
}

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
        if SIMPLE[entry.type] then
            text = tostring(owner[entry.name])
        elseif entry.type == "ObjectProperty" then
            local o = owner[entry.name]
            text = valid(o) and o:GetFullName() or "nil"
        elseif entry.type == "StructProperty" and entry.fields ~= nil then
            local value, parts = owner[entry.name], {}
            for _, field in ipairs(entry.fields) do
                local inner = read(value, field)
                if inner ~= nil then
                    parts[#parts + 1] = field.name .. "=" .. inner
                end
            end
            text = "<" .. tostring(entry.struct) .. "> {" .. table.concat(parts, " ") .. "}"
        end
    end)
    return text
end

local function dump(object, title)
    out("== " .. title .. " " .. object:GetFullName())
    local class = object:GetClass()
    local depth = 0
    while valid(class) and depth < 4 do
        local full = class:GetFullName()
        if full:find("/Script/Engine.", 1, true) or full:find("/Script/CoreUObject.", 1, true) then
            break
        end
        out("  class " .. full)
        for _, entry in ipairs(props_of(class, 2)) do
            local text = read(object, entry)
            out("    " .. entry.name .. ":" .. entry.type .. (text and (" = " .. text) or ""))
        end
        local functions = {}
        pcall(function()
            class:ForEachFunction(function(fn)
                functions[#functions + 1] = fn:GetFName():ToString()
            end)
        end)
        out("    funcs " .. table.concat(functions, ", "))
        class = class:GetSuperStruct()
        depth = depth + 1
    end
end

local elevator = nil
for _, found in ipairs(FindAllOf("BP_ElevatorFinal_C") or {}) do
    if valid(found) then
        elevator = found
    end
end
if elevator == nil then
    out("no elevator")
    return
end

local at = elevator:K2_GetActorLocation()
out(string.format("car %.1f %.1f %.1f", at.X, at.Y, at.Z))

local lib = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
local PARTS = { "ElevatorMesh", "CollisionBox", "SM_Lift_01_01", "SM_Lift_01_03", "SM_Lift_01_Door_01", "SM_Lift_01_Door_02",
    "SM_Lift_01_Door_03", "SM_Lift_01_Door_04", "SM_Lift_01_Lamp_01", "SM_Lift_01_Lamp_02", "SpotLight", "SpotLight1", "Sphere2" }
for _, name in ipairs(PARTS) do
    local part = elevator[name]
    if valid(part) then
        local line = name
        pcall(function()
            local rel, world, rot, scale = part.RelativeLocation, part:K2_GetComponentLocation(), part.RelativeRotation, part.RelativeScale3D
            line = line .. string.format(" rel %.1f %.1f %.1f rot p%.1f y%.1f r%.1f scale %.2f %.2f %.2f world %.1f %.1f %.1f", rel.X, rel.Y, rel.Z,
                rot.Pitch, rot.Yaw, rot.Roll, scale.X, scale.Y, scale.Z, world.X, world.Y, world.Z)
        end)
        pcall(function()
            local origin, extent, radius = {}, {}, {}
            lib:GetComponentBounds(part, origin, extent, radius)
            line = line .. string.format(" | bounds centre %.1f %.1f %.1f half %.1f %.1f %.1f", origin.X, origin.Y, origin.Z, extent.X, extent.Y, extent.Z)
        end)
        pcall(function()
            local up = part:GetAttachParent()
            if valid(up) then
                line = line .. " | under " .. up:GetFName():ToString()
            end
        end)
        pcall(function()
            if valid(part.StaticMesh) then
                line = line .. " | mesh " .. part.StaticMesh:GetFName():ToString()
            end
        end)
        pcall(function()
            line = line .. " | collision " .. tostring(part:GetCollisionEnabled()) .. " visible " .. tostring(part:IsVisible())
        end)
        pcall(function()
            if part.BoxExtent ~= nil then
                line = line .. string.format(" | box %.1f %.1f %.1f", part.BoxExtent.X, part.BoxExtent.Y, part.BoxExtent.Z)
            end
        end)
        out(line)
    else
        out(name .. " missing")
    end
end

if valid(elevator.ElevatorMovement) then
    dump(elevator.ElevatorMovement, "MOVEMENT")
end
if valid(elevator.ElevatorPanel) then
    local panel = elevator.ElevatorPanel
    local p = panel:K2_GetActorLocation()
    out(string.format("panel actor at %.1f %.1f %.1f", p.X, p.Y, p.Z))
    dump(panel, "PANEL")
end
if valid(elevator.Timeline) then
    local timeline = elevator.Timeline
    pcall(function()
        out("door timeline length " .. tostring(timeline:GetTimelineLength()) .. " playing " .. tostring(timeline:IsPlaying())
            .. " position " .. tostring(timeline:GetPlaybackPosition()))
    end)
end

for _, controller in ipairs(FindAllOf("PlayerController") or {}) do
    if valid(controller) and valid(controller.Pawn) then
        local pawn = controller.Pawn
        local p = pawn:K2_GetActorLocation()
        local half = -1
        pcall(function()
            half = pawn.CapsuleComponent:GetScaledCapsuleHalfHeight()
        end)
        out(string.format("pawn %.1f %.1f %.1f capsule half height %.1f", p.X, p.Y, p.Z, half))
    end
end
