-- Lists the parameters of the elevator's functions. Reads only.
-- Run with: python scripts/live.py scripts/probes/elevator_funcs.lua   (the game must be on Level 0)

local function valid(o)
    if o == nil or type(o) ~= "userdata" then
        return false
    end
    local ok, result = pcall(function()
        return o:IsValid()
    end)
    return ok and result == true
end

local function params(class)
    pcall(function()
        class:ForEachFunction(function(fn)
            local parts = {}
            pcall(function()
                fn:ForEachProperty(function(prop)
                    local text = prop:GetFName():ToString() .. ":" .. prop:GetClass():GetFName():ToString()
                    pcall(function()
                        local inner = prop:GetStruct()
                        if valid(inner) then
                            text = text .. "<" .. inner:GetFName():ToString() .. ">"
                        end
                    end)
                    parts[#parts + 1] = text
                end)
            end)
            local flags = ""
            pcall(function()
                flags = string.format(" flags 0x%X", fn:GetFunctionFlags())
            end)
            out("  " .. fn:GetFName():ToString() .. "(" .. table.concat(parts, ", ") .. ")" .. flags)
        end)
    end)
end

for _, path in ipairs({
    "/Script/BETGame.ElevatorMovementComponent",
    "/Script/BETGame.Level0Elevator",
    "/Script/BETGame.Elevator_Base",
    "/Game/Features/Objectives/Levels/Level_0/Elevator/BP_ElevatorFinal.BP_ElevatorFinal_C",
}) do
    local class = StaticFindObject(path)
    out(path .. (valid(class) and "" or "  MISSING"))
    if valid(class) then
        params(class)
    end
end

local elevator = FindFirstOf("BP_ElevatorFinal_C")
if valid(elevator) then
    local move = elevator.ElevatorMovement
    pcall(function()
        out("moving " .. tostring(move:GetIsMoving()) .. " alpha " .. tostring(move:GetMoveAlpha()))
    end)
    pcall(function()
        out("component tick enabled " .. tostring(move:IsComponentTickEnabled()))
    end)
    pcall(function()
        local gs = elevator:GetWorld().GameState
        out("server time " .. tostring(gs:GetServerWorldTimeSeconds()) .. " match state " .. gs.MatchState:ToString())
    end)
    pcall(function()
        out("doors open " .. tostring(elevator.DoorsOpen) .. " alpha " .. tostring(elevator.CurrentDoorAlpha) .. " closing " .. tostring(elevator.bAreDoorsClosing)
            .. " leave " .. tostring(elevator.LeaveOnDoorsClosed) .. " players in " .. tostring(elevator.PlayersInElevator))
    end)
    pcall(function()
        local box = elevator.CollisionBox
        out(string.format("collision box extent %.1f %.1f %.1f", box.BoxExtent.X, box.BoxExtent.Y, box.BoxExtent.Z))
    end)
end
