-- Read-mostly probe: which of the calls the mod uses to switch a mesh off is the slow one.
-- It repeats those calls on the level's chunk manager meshes, which the mod has already switched off,
-- so nothing changes for the player. Run it on a built floor: python scripts/live.py scripts/probes/hide_cost.lua
local list = FindAllOf("StaticMeshComponent") or {}
local seen = 0
for _, component in ipairs(list) do
    if component:IsValid() then
        local owner = component:GetOwner()
        if owner:IsValid() and owner:GetFullName():find("ChunkManager", 1, true) then
            seen = seen + 1
            local class = component:GetClass():GetFullName()
            local instances = -1
            pcall(function() instances = component:GetInstanceCount() end)
            local children = -1
            pcall(function() children = component:GetNumChildrenComponents() end)
            local function timed(name, fn)
                local t0 = os.clock()
                local ok = pcall(fn)
                return string.format("%s %.0f ms%s", name, (os.clock() - t0) * 1000, ok and "" or " (failed)")
            end
            local parts = {
                timed("hidden", function() component:SetHiddenInGame(true, true) end),
                timed("visibility", function() component:SetVisibility(false, true) end),
                timed("collision", function() component:SetCollisionEnabled(0) end),
                timed("scale", function() component:SetWorldScale3D({ X = 0.002, Y = 0.002, Z = 0.002 }) end),
                timed("scale back", function() component:SetWorldScale3D({ X = 0.001, Y = 0.001, Z = 0.001 }) end),
            }
            out(string.format("%s | instances %s | attached %s | %s", class, tostring(instances), tostring(children),
                table.concat(parts, ", ")))
            if seen >= 12 then
                break
            end
        end
    end
end
out("chunk manager meshes looked at: " .. seen .. " of " .. #list .. " static mesh components")
