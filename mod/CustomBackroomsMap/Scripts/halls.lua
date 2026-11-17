-- Flickering Halls: the generated floor, its tricks, and the way out.
-- Loaded by main.lua, which calls H.enter, H.tick, H.use and H.message.
-- Rooms and furniture are engine basic shapes. The monster is the game's Skin Stealer and the
-- things you pick up are the game's own pickups, so they go into the real inventory.

local ctx = ...
local H = {}
local log = (ctx and ctx.log) or function(text) print("[CBR] " .. tostring(text)) end

local CELL = 800
local HEIGHT = 320
local BAND = 96
local TH = 10
local DOOR_W = 320
local DOOR_H = 264
local SIGN_Z = 292
local SEG = 800
local SEGS = 8
local PASSES = 5
local HALL_HALF = 200
local FAKE_LEN = 900
local EPI_HALF = 240
local USE_RANGE = 270
local ZERO = { Pitch = 0, Yaw = 0, Roll = 0 }
local MONSTER_CLASS = "/Game/Entities/SkinStealer/BP_SkinStealer.BP_SkinStealer_C"
-- The game hands a monster its jumpscare through this set. One we spawn ourselves starts without it.
local MONSTER_ABILITIES = "/Game/Entities/SkinStealer/Blueprints/Data/DA_SkinStealerAbilitySet.DA_SkinStealerAbilitySet"
local ITEM_ROOT = "/Game/Player/Features/Inventory/Items/"
-- Level item id -> the game's own item.
local GAME_ITEMS = {
    granola = "GranolaSquare/BP_GranolaSquare_Definition",
    canned_soup = "CannedSoup/BP_CannedSoup_Definition",
    almond_water = "AlmondWater/BP_AlmondWater_Definition",
    vhs = "VHSTape/BP_Level0Tape_Definition",
    fuse = "Fuse/BP_Fuse_Definition",
    valve = "Valve/BP_GreenValve_Definition",
    small_key = "SmallKey/BP_SmallKey_Definition",
}
local GLOWS = {
    vhs = { 0.6, 0.7, 1.0 }, fuse = { 0.5, 1.0, 1.0 }, valve = { 0.5, 1.0, 0.5 }, small_key = { 1.0, 0.85, 0.4 },
}
local BLACKOUT_TAG = "Event.Blackout"
local DARK_K = 0.04
local LEAD_AFTER = 6
local LEAD_STOP = 280

local THEMES = {
    yellow_wallpaper = {
        wall = { 0.70, 0.54, 0.13 }, band = { 0.50, 0.36, 0.07 }, floor = { 0.25, 0.18, 0.06 },
        ceil = { 0.68, 0.65, 0.52 }, trim = { 0.36, 0.25, 0.05 }, light = { 1.0, 0.84, 0.55 }, power = 1.0,
    },
    damp_office = {
        wall = { 0.47, 0.50, 0.34 }, band = { 0.28, 0.31, 0.20 }, floor = { 0.13, 0.17, 0.19 },
        ceil = { 0.60, 0.61, 0.54 }, trim = { 0.20, 0.22, 0.15 }, light = { 0.86, 0.95, 0.78 }, power = 0.9,
    },
    pool_tile = {
        wall = { 0.78, 0.85, 0.86 }, band = { 0.10, 0.46, 0.58 }, floor = { 0.50, 0.68, 0.73 },
        ceil = { 0.76, 0.80, 0.80 }, trim = { 0.08, 0.36, 0.46 }, light = { 0.74, 0.90, 1.0 }, power = 1.05,
    },
    concrete_hall = {
        wall = { 0.33, 0.33, 0.32 }, band = { 0.22, 0.22, 0.21 }, floor = { 0.12, 0.12, 0.12 },
        ceil = { 0.27, 0.27, 0.27 }, trim = { 0.15, 0.15, 0.15 }, light = { 1.0, 0.92, 0.82 }, power = 0.7,
    },
    drop_ceiling = {
        wall = { 0.63, 0.47, 0.10 }, band = { 0.43, 0.31, 0.06 }, floor = { 0.21, 0.15, 0.05 },
        ceil = { 0.70, 0.68, 0.57 }, trim = { 0.31, 0.21, 0.04 }, light = { 1.0, 0.80, 0.47 }, power = 0.85,
    },
}
local STEEL = { 0.20, 0.21, 0.23 }
local DARK = { 0.05, 0.05, 0.05 }
local WOOD = { 0.24, 0.14, 0.06 }
local WHITE = { 1.0, 1.0, 0.95 }
local RED = { 0.55, 0.04, 0.03 }
local GREEN = { 0.08, 0.62, 0.14 }
local CRATE = { 0.42, 0.30, 0.16 }
local SIDE_YAW = { E = 180, W = 0, N = -90, S = 90 }
local DIRS = { E = { 1, 0 }, W = { -1, 0 }, N = { 0, 1 }, S = { 0, -1 } }
local PART_LABEL = { vhs = "TAPE", valve = "VALVE", fuse = "FUSE" }
local WHISPERS = {
    "You have stood in this room before. You were taller.",
    "The hum drops a note when you stop walking.",
    "Somebody counted these rooms and wrote down seventeen.",
    "The carpet is warm where nobody has been.",
}

local G = nil
local HUD = rawget(_G, "CBR_HUD")

local function shade(color, k)
    return { color[1] * k, color[2] * k, color[3] * k }
end

-- A line of text for this floor. The level file can carry its own wording under `text`, so a floor
-- written from a wiki page reads like that page. Whatever the file leaves out falls back to the
-- line given here. {name} in a line is filled in from vars.
local function LT(level, key, fallback, vars)
    local text = fallback
    local set = level ~= nil and level.text or nil
    if type(set) == "table" and type(set[key]) == "string" and set[key] ~= "" then
        text = set[key]
    end
    if vars ~= nil then
        for name, value in pairs(vars) do
            text = text:gsub("{" .. name .. "}", function()
                return tostring(value)
            end)
        end
    end
    return text
end

local function L(key, fallback, vars)
    return LT(G ~= nil and G.level or nil, key, fallback, vars)
end

-- The look of a room. The level file can define its own themes; a field it leaves out comes from
-- bare concrete.
local function theme_of(room)
    if room ~= nil and G.themes ~= nil and G.themes[room.theme] ~= nil then
        return G.themes[room.theme]
    end
    return (room ~= nil and THEMES[room.theme]) or THEMES.yellow_wallpaper
end

local function valid(obj)
    if obj == nil then
        return false
    end
    local ok, result = pcall(function()
        return obj:IsValid()
    end)
    return ok and result == true
end

-- The name of an item definition, or nil when a slot or pickup has none. Asking a missing object for
-- its name takes the whole game down, and pcall does not catch that.
local function def_name(def)
    if not valid(def) then
        return nil
    end
    return def:GetFName():ToString()
end

local function W(lx, ly, lz)
    return { X = G.O.x + lx, Y = G.O.y + ly, Z = G.O.z + (lz or 0) }
end

local function asset(path)
    local obj = StaticFindObject(path)
    if not valid(obj) then
        pcall(LoadAsset, path)
        obj = StaticFindObject(path)
    end
    if valid(obj) then
        return obj
    end
    return nil
end

local function find_controller()
    for _, controller in ipairs(FindAllOf("PlayerController") or {}) do
        local isLocal = false
        pcall(function()
            isLocal = controller:IsLocalController()
        end)
        if isLocal and valid(controller) then
            return controller
        end
    end
    return FindFirstOf("PlayerController")
end

local function survivors()
    local list = FindAllOf("BP_Survivor_Character_C")
    if list ~= nil and #list > 0 then
        return list
    end
    return {}
end

local function track(actor)
    G.actors[#G.actors + 1] = actor
    pcall(function()
        G.ours[actor:GetFullName()] = true
    end)
    return actor
end

local function destroy(actor)
    pcall(function()
        if valid(actor) then
            actor:K2_DestroyActor()
        end
    end)
end

local function paint(actor, color)
    local comp = actor.StaticMeshComponent
    local key = string.format("%.3f,%.3f,%.3f", color[1], color[2], color[3])
    local mid = G.mids[key]
    if valid(mid) then
        comp:SetMaterial(0, mid)
        return
    end
    mid = comp:CreateDynamicMaterialInstance(0, G.basic, FName("None"))
    mid:SetVectorParameterValue(FName("Color"), { R = color[1], G = color[2], B = color[3], A = 1 })
    G.mids[key] = mid
end

-- What a generated piece is called in a hand-made layout: its shape, place and size in whole units.
-- unreal/cbr_layout.py builds the same key, so a piece deleted in the Unreal editor can be found here.
local function piece_key(kind, lx, ly, lz, sx, sy, sz)
    local function r(value)
        return math.floor(value + 0.5)
    end
    return string.format("%s|%d|%d|%d|%d|%d|%d", kind, r(lx), r(ly), r(lz), r(sx), r(sy), r(sz))
end

-- One basic shape, centred at local x, y, z with a size in world units.
local function shape(kind, lx, ly, lz, sx, sy, sz, color, opt)
    opt = opt or {}
    local actor = G.world:SpawnActor(G.cls.mesh, W(lx, ly, lz), opt.rot or ZERO)
    if not valid(actor) then
        return nil
    end
    local comp = actor.StaticMeshComponent
    comp:SetMobility(2)
    comp:SetStaticMesh(G.mesh[kind])
    paint(actor, color)
    actor:SetActorScale3D({ X = sx / 100, Y = sy / 100, Z = sz / 100 })
    if opt.ghost then
        actor:SetActorEnableCollision(false)
        pcall(function()
            comp:SetCanEverAffectNavigation(false)
        end)
    end
    if opt.noshadow then
        pcall(function()
            comp:SetCastShadow(false)
        end)
    end
    if (G.removed ~= nil or G.record ~= nil) and not opt.custom then
        local key = piece_key(kind, lx, ly, lz, sx, sy, sz)
        -- Taken out by hand in the editor. It stays as an actor, unseen and untouchable, because
        -- doors, plugs and the crate hold on to their pieces.
        if G.removed ~= nil and G.removed[key] then
            G.removedCount = (G.removedCount or 0) + 1
            pcall(function()
                actor:SetActorHiddenInGame(true)
                actor:SetActorEnableCollision(false)
            end)
            pcall(function()
                comp:SetCanEverAffectNavigation(false)
            end)
        end
        if G.record ~= nil then
            local rot = opt.rot or ZERO
            G.record[#G.record + 1] = {
                type = "piece", key = key, kind = kind, at = { lx, ly, lz }, size = { sx, sy, sz },
                rot = { rot.Pitch or 0, rot.Yaw or 0, rot.Roll or 0 }, color = { color[1], color[2], color[3] },
                ghost = opt.ghost == true, noshadow = opt.noshadow == true,
            }
        end
    end
    return track(actor)
end

local function box(x0, y0, z0, x1, y1, z1, color, opt)
    return shape("cube", (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2,
        math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0), color, opt)
end

local function apply_light(rec)
    pcall(function()
        rec.comp:SetIntensity(rec.base * rec.k * G.lightK)
    end)
end

local function light(lx, ly, lz, intensity, radius, color, room, loose)
    local actor = G.world:SpawnActor(G.cls.point, W(lx, ly, lz), ZERO)
    if not valid(actor) then
        return nil
    end
    local comp = actor.PointLightComponent
    pcall(function()
        comp:SetMobility(2)
    end)
    comp:SetIntensity(intensity)
    comp:SetAttenuationRadius(radius)
    comp:SetLightColor({ R = color[1], G = color[2], B = color[3], A = 1 }, true)
    pcall(function()
        comp:SetCastShadows(G.shadows == true and not loose)
    end)
    track(actor)
    if G.record ~= nil and not G.recordOff then
        G.record[#G.record + 1] = {
            type = "light", at = { lx, ly, lz }, intensity = intensity, radius = radius,
            color = { color[1], color[2], color[3] }, always = loose == true,
        }
    end
    local rec = { actor = actor, comp = comp, base = intensity, k = 1, room = room }
    if not loose then
        G.lights[#G.lights + 1] = rec
    end
    return rec
end

local function sign(lx, ly, lz, yaw, text, size, color)
    local actor = G.world:SpawnActor(G.cls.text, W(lx, ly, lz), { Pitch = 0, Yaw = yaw, Roll = 0 })
    if not valid(actor) then
        return nil
    end
    local comp = actor.TextRender
    pcall(function()
        comp:SetMobility(2)
    end)
    comp:SetText(FText(text))
    comp:SetWorldSize(size)
    comp:SetTextRenderColor({ R = color[1], G = color[2], B = color[3], A = 255 })
    comp:SetHorizontalAlignment(1)
    pcall(function()
        comp:SetVerticalAlignment(1)
    end)
    track(actor)
    if G.record ~= nil and not G.recordOff then
        G.record[#G.record + 1] = {
            type = "text", at = { lx, ly, lz }, yaw = yaw, text = text, size = size,
            color = { color[1], color[2], color[3] },
        }
    end
    return { actor = actor, comp = comp, text = text }
end

-- What was placed by hand in the Unreal editor (levels/<level>.editor.lua): extra shapes, lamps and
-- lettering. A lamp goes dark with the others during a hunt unless it is marked to stay lit.
local function build_editor()
    local editor = G.level.editor
    if type(editor) ~= "table" then
        return
    end
    G.recordOff = true
    local pieces, lamps, texts = 0, 0, 0
    for _, piece in ipairs(editor.pieces or {}) do
        if G.mesh[piece.kind] ~= nil then
            local rot = piece.rot or { 0, 0, 0 }
            local made = shape(piece.kind, piece.at[1], piece.at[2], piece.at[3], piece.size[1], piece.size[2], piece.size[3],
                piece.color or { 0.5, 0.5, 0.5 },
                { rot = { Pitch = rot[1], Yaw = rot[2], Roll = rot[3] }, ghost = piece.ghost == true,
                    noshadow = piece.noshadow == true, custom = true })
            if made ~= nil then
                pieces = pieces + 1
            end
        end
    end
    for _, lamp in ipairs(editor.lights or {}) do
        if light(lamp.at[1], lamp.at[2], lamp.at[3], lamp.intensity or 9000, lamp.radius or 900,
                lamp.color or { 1, 1, 1 }, nil, lamp.always == true) ~= nil then
            lamps = lamps + 1
        end
    end
    for _, text in ipairs(editor.texts or {}) do
        local color = text.color or { 255, 255, 255 }
        if sign(text.at[1], text.at[2], text.at[3], text.yaw or 0, tostring(text.text or ""), text.size or 24, color) ~= nil then
            texts = texts + 1
        end
    end
    G.recordOff = false
    G.editorCount = { pieces = pieces, lights = lamps, texts = texts, removed = G.removedCount or 0 }
    log("Hand-made layout: " .. pieces .. " pieces, " .. lamps .. " lamps, " .. texts .. " texts added, "
        .. (G.removedCount or 0) .. " generated pieces taken out")
end

local function set_sign(rec, text)
    if rec == nil or rec.text == text then
        return
    end
    rec.text = text
    pcall(function()
        rec.comp:SetText(FText(text))
    end)
end

-- Timers, moves and subtitles all run from H.tick so a reload drops them cleanly.
local function after(seconds, fn)
    G.timers[#G.timers + 1] = { at = os.clock() + seconds, fn = fn }
end

local function slide(actor, lx, ly, z0, z1, seconds, done)
    G.anims[#G.anims + 1] = { actor = actor, lx = lx, ly = ly, z0 = z0, z1 = z1, t0 = os.clock(), dur = seconds, done = done }
end

local function say(text, seconds, kind)
    if kind == "room" then
        for index = #G.subs, 1, -1 do
            if G.subs[index].kind == "room" then
                table.remove(G.subs, index)
            end
        end
        if G.sub ~= nil and G.sub.kind == "room" then
            G.sub.untilT = 0
        end
    end
    G.subs[#G.subs + 1] = { text = text, dur = seconds or 4, kind = kind }
end

local function sfx(name, volume)
    local sound = G.snd[name]
    if not valid(sound) or not valid(G.pawn) then
        return
    end
    pcall(function()
        G.gs:PlaySound2D(G.pawn, sound, volume or 1.0, 1.0, 0.0, nil, nil, true)
    end)
end

local function fade(from, to, seconds, color, hold)
    pcall(function()
        G.pc.PlayerCameraManager:StartCameraFade(from, to, seconds,
            { R = color[1], G = color[2], B = color[3], A = 1 }, false, hold == true)
    end)
end

local function set_lights(k)
    G.lightK = k
    for _, rec in ipairs(G.lights) do
        apply_light(rec)
    end
end

local function blackout(seconds, done)
    set_lights(0)
    after(seconds, function()
        set_lights(G.hunt ~= nil and DARK_K or 1)
        if done then
            done()
        end
    end)
end

local function in_view(lx, ly, lz, minDot)
    local dx, dy, dz = lx - G.cam.x, ly - G.cam.y, (lz or 150) - G.cam.z
    local d = math.sqrt(dx * dx + dy * dy + dz * dz)
    if d < 1 then
        return true
    end
    return (dx * G.fwd.X + dy * G.fwd.Y + dz * G.fwd.Z) / d > (minDot or 0.35)
end

local function dist_to(lx, ly)
    local dx, dy = lx - G.px, ly - G.py
    return math.sqrt(dx * dx + dy * dy)
end

local function teleport(lx, ly, yaw)
    pcall(function()
        G.pawn.CharacterMovement.Velocity = { X = 0, Y = 0, Z = 0 }
    end)
    pcall(function()
        G.pawn:K2_SetActorLocation(W(lx, ly, 110), false, {}, true)
    end)
    -- The rest of this tick must not act on the position from before the jump.
    G.px, G.py = lx, ly
    if yaw ~= nil then
        pcall(function()
            G.pc:SetControlRotation({ Pitch = 0, Yaw = yaw, Roll = 0 })
        end)
    end
end

local function room_center(room)
    return room.x * CELL + CELL / 2, room.y * CELL + CELL / 2
end

local function neighbors(room)
    local found = {}
    for dir, d in pairs(DIRS) do
        local other = G.grid[(room.x + d[1]) .. "_" .. (room.y + d[2])]
        if other ~= nil and G.links[room.id .. "|" .. other.id] ~= nil then
            found[#found + 1] = { room = other, dir = dir }
        end
    end
    table.sort(found, function(a, b)
        return a.room.id < b.room.id
    end)
    return found
end

-- A slab on the inside face of one side of a room. a0..a1 run along that side.
local function side_box(room, dir, a0, a1, z0, z1, color, d0, d1, opt)
    local x0, y0 = room.x * CELL, room.y * CELL
    d0 = d0 or 0
    d1 = d1 or TH
    if dir == "E" then
        return box(x0 + CELL - d1, y0 + a0, z0, x0 + CELL - d0, y0 + a1, z1, color, opt)
    elseif dir == "W" then
        return box(x0 + d0, y0 + a0, z0, x0 + d1, y0 + a1, z1, color, opt)
    elseif dir == "N" then
        return box(x0 + a0, y0 + CELL - d1, z0, x0 + a1, y0 + CELL - d0, z1, color, opt)
    end
    return box(x0 + a0, y0 + d0, z0, x0 + a1, y0 + d1, z1, color, opt)
end

local function side_point(room, dir, a, depth)
    local x0, y0 = room.x * CELL, room.y * CELL
    if dir == "E" then
        return x0 + CELL - depth, y0 + a
    elseif dir == "W" then
        return x0 + depth, y0 + a
    elseif dir == "N" then
        return x0 + a, y0 + CELL - depth
    end
    return x0 + a, y0 + depth
end

local function side_kind(room, dir)
    local d = DIRS[dir]
    local other = G.grid[(room.x + d[1]) .. "_" .. (room.y + d[2])]
    if other == nil then
        if room.id == G.level.exit.room and dir == "E" then
            return "exit"
        end
        if room.id == G.fakeRoom and dir == "W" then
            return "fake"
        end
        return "solid"
    end
    local link = G.links[room.id .. "|" .. other.id]
    if link == nil then
        return "solid"
    end
    return "door", link, other
end

-- Fill a doorway so it reads as plain wall from both rooms. The frame stays.
local function plug(room, dir, other)
    local th = theme_of(room)
    local oth = (other and theme_of(other)) or th
    local g0, g1 = CELL / 2 - DOOR_W / 2, CELL / 2 + DOOR_W / 2
    return {
        side_box(room, dir, g0, g1, 0, BAND, th.band, 0, TH - 0.5),
        side_box(room, dir, g0, g1, BAND, DOOR_H, th.wall, 0, TH - 0.5),
        side_box(room, dir, g0, g1, 0, BAND, oth.band, -TH + 0.5, 0),
        side_box(room, dir, g0, g1, BAND, DOOR_H, oth.wall, -TH + 0.5, 0),
    }
end

local function build_exit_door(room)
    local xw = G.w * CELL
    local _, yc = room_center(room)
    local slab = box(xw - 8, yc - DOOR_W / 2, 0, xw + 8, yc + DOOR_W / 2, DOOR_H, STEEL)
    G.exit = { state = "shut", slab = slab, lx = xw, ly = yc, lamps = {} }
    box(xw - 13, yc - 60, 110, xw - 8, yc + 60, 118, { 0.75, 0.6, 0.05 }, { ghost = true })
    sign(xw - TH - 3, yc, SIGN_Z, 180, L("exitSign", "MAINTENANCE"), 30, { 255, 210, 60 })
    for index, id in ipairs(G.level.exit.requires) do
        local y = yc + DOOR_W / 2 + 40 + (index - 1) * 46
        local lamp = box(xw - TH - 6, y - 9, 150, xw - TH, y + 9, 168, RED, { ghost = true })
        G.exit.lamps[id] = lamp
        sign(xw - TH - 3, y, 136, 180, PART_LABEL[id] or id:upper(), 11, { 230, 230, 230 })
    end
end

local function build_hall()
    local x0 = G.w * CELL
    local _, yc = room_center(G.grid[G.exitKey])
    local wall, band, floor, ceil = { 0.30, 0.30, 0.29 }, { 0.19, 0.19, 0.18 }, { 0.10, 0.10, 0.10 }, { 0.22, 0.22, 0.22 }
    G.hall = { x0 = x0, yc = yc, passes = 0, lights = {}, signs = {}, white = false }
    for k = 0, SEGS - 1 do
        local a, b = x0 + k * SEG, x0 + (k + 1) * SEG
        box(a, yc - HALL_HALF, -20, b, yc + HALL_HALF, 0, floor)
        box(a, yc - HALL_HALF, HEIGHT, b, yc + HALL_HALF, HEIGHT + 10, ceil)
        for _, s in ipairs({ -1, 1 }) do
            local y = yc + s * HALL_HALF
            box(a, math.min(y, y + s * TH), 0, b, math.max(y, y + s * TH), BAND, band)
            box(a, math.min(y, y + s * TH), BAND, b, math.max(y, y + s * TH), HEIGHT, wall)
        end
        shape("cyl", (a + b) / 2, yc + HALL_HALF - 34, HEIGHT - 30, 16, 16, SEG, { 0.42, 0.06, 0.04 },
            { rot = { Pitch = 90, Yaw = 0, Roll = 0 }, ghost = true })
        box((a + b) / 2 - 70, yc - 30, HEIGHT - 5, (a + b) / 2 + 70, yc + 30, HEIGHT - 1, WHITE, { ghost = true })
        G.hall.lights[k + 1] = light((a + b) / 2, yc, HEIGHT - 60, 18000, 900, { 0.80, 0.90, 1.0 }, "hall")
        box(a + 396, yc - 95, 258, a + 404, yc + 95, 296, { 0.03, 0.16, 0.06 }, { ghost = true })
        G.hall.signs[k + 1] = sign(a + 394, yc, 277, 180, "", 24, { 190, 255, 200 })
        if G.level.rules.exitPipes then
            -- More pipes and dials the further in, the way the wiki has this level turn into the next.
            local thin = { ghost = true, noshadow = true }
            if k >= 3 then
                shape("cyl", (a + b) / 2, yc - HALL_HALF + 30, HEIGHT - 40, 22, 22, SEG, { 0.30, 0.31, 0.33 },
                    { rot = { Pitch = 90, Yaw = 0, Roll = 0 }, ghost = true, noshadow = true })
            end
            if k >= 5 then
                shape("cyl", (a + b) / 2, yc - HALL_HALF + 24, 60, 12, 12, SEG, { 0.36, 0.17, 0.08 },
                    { rot = { Pitch = 90, Yaw = 0, Roll = 0 }, ghost = true, noshadow = true })
            end
            for d = 1, math.min(k, 3) do
                local side = ((k + d) % 2 == 0) and -1 or 1
                shape("cyl", a + d * SEG / 4, yc + side * (HALL_HALF - 3), 150 + (d % 2) * 26, 34, 34, 6, { 0.80, 0.80, 0.74 },
                    { rot = { Pitch = 0, Yaw = 0, Roll = 90 }, ghost = true, noshadow = true })
            end
        end
    end
    local xe = x0 + SEGS * SEG
    box(xe, yc - HALL_HALF - TH, 0, xe + TH, yc + HALL_HALF + TH, HEIGHT, { 0.08, 0.08, 0.08 })
    box(x0 + 216, yc - 170, 252, x0 + 224, yc + 170, 300, { 0.20, 0.02, 0.02 }, { ghost = true })
    sign(x0 + 214, yc, 276, 180, L("hallSign", "DO NOT LOOK BACK"), 30, { 255, 235, 225 })
    G.hall.xe = xe
end

local function hall_refresh()
    local hall = G.hall
    for k = 0, SEGS - 1 do
        local metres = (PASSES + SEGS - k - hall.passes) * 100
        set_sign(hall.signs[k + 1], hall.white and "EXIT" or ("EXIT " .. metres .. " m"))
        local rec = hall.lights[k + 1]
        if rec ~= nil and not hall.white then
            rec.k = math.max(0.3, 1 - hall.passes * 0.14)
            apply_light(rec)
        end
    end
end

local function build_fake_exit(room)
    local _, yc = room_center(room)
    local wall, floor = { 0.26, 0.26, 0.25 }, { 0.09, 0.09, 0.09 }
    G.fake = { state = "open", yc = yc, room = room }
    box(-FAKE_LEN, yc - DOOR_W / 2, -20, 0, yc + DOOR_W / 2, 0, floor)
    box(-FAKE_LEN, yc - DOOR_W / 2, DOOR_H, 0, yc + DOOR_W / 2, DOOR_H + 10, wall)
    box(-FAKE_LEN, yc - DOOR_W / 2 - TH, 0, 0, yc - DOOR_W / 2, DOOR_H, wall)
    box(-FAKE_LEN, yc + DOOR_W / 2, 0, 0, yc + DOOR_W / 2 + TH, DOOR_H, wall)
    box(-FAKE_LEN - TH, yc - DOOR_W / 2 - TH, 0, -FAKE_LEN, yc + DOOR_W / 2 + TH, DOOR_H, wall)
    light(-FAKE_LEN + 120, yc, 180, 12000, 700, { 1.0, 0.12, 0.08 }, "fake")
    G.fake.plate = box(TH, yc - 70, SIGN_Z - 21, TH + 4, yc + 70, SIGN_Z + 21, { 0.30, 0.02, 0.02 }, { ghost = true })
    G.fake.sign = sign(TH + 6, yc, SIGN_Z, 0, "EXIT", 30, { 255, 235, 225 })
    sign(-FAKE_LEN + 3, yc, 150, 0, "EXIT", 40, { 255, 40, 30 })
end

local function build_epilogue()
    local cx = G.hall.xe + 1200
    local cy = G.hall.yc
    local wall, band = { 0.42, 0.44, 0.47 }, { 0.27, 0.28, 0.30 }
    local a, b, c, d = cx - EPI_HALF, cx + EPI_HALF, cy - EPI_HALF, cy + EPI_HALF
    G.epi = { cx = cx, cy = cy, state = "idle" }
    box(a, c, -20, b, d, 0, { 0.10, 0.10, 0.11 })
    box(a, c, 280, b, d, 290, { 0.30, 0.31, 0.33 })
    for _, part in ipairs({
        { a - TH, c - TH, a, d + TH }, { a - TH, c - TH, b + TH, c }, { a - TH, d, b + TH, d + TH },
        { b, c - TH, b + TH, cy - 90 }, { b, cy + 90, b + TH, d + TH },
    }) do
        box(part[1], part[2], 0, part[3], part[4], BAND, band)
        box(part[1], part[2], BAND, part[3], part[4], 280, wall)
    end
    box(b, cy - 90, 220, b + TH, cy + 90, 280, wall)
    G.epi.door = box(b + 1, cy - 90, 0, b + TH - 1, cy + 90, 220, { 0.52, 0.54, 0.57 })
    G.epi.doorX = b
    box(a + 4, c + 4, 275, b - 4, d - 4, 279, WHITE, { ghost = true })
    G.epi.light = light(cx, cy, 220, 26000, 800, { 0.92, 0.96, 1.0 }, "epi")
    G.epi.sign = sign(b - 3, cy, 246, 180, "- -", 30, { 255, 150, 40 })
    shape("sphere", b - 5, cy + 120, 120, 12, 12, 12, { 0.85, 0.65, 0.05 }, { ghost = true })
    box(b + 200, cy - 200, 0, b + 210, cy + 200, 300, WHITE, { ghost = true })
    box(b + TH, cy - 200, -20, b + 210, cy + 200, 0, WHITE)
    box(b + TH, cy - 210, 0, b + 210, cy - 200, 300, WHITE, { ghost = true })
    box(b + TH, cy + 200, 0, b + 210, cy + 210, 300, WHITE, { ghost = true })
    box(b + TH, cy - 200, 290, b + 210, cy + 200, 300, WHITE, { ghost = true })
    G.epi.glow = light(b + 110, cy, 150, 0, 900, { 1, 1, 1 }, "epi")
    G.epi.glow.base = 80000
    G.epi.glow.k = 0
end

local function build_side(room, dir, th)
    local kind, link, other = side_kind(room, dir)
    local g0, g1 = CELL / 2 - DOOR_W / 2, CELL / 2 + DOOR_W / 2
    local thin = { ghost = true, noshadow = true }
    if kind == "solid" then
        side_box(room, dir, 0, CELL, 0, BAND, th.band)
        side_box(room, dir, 0, CELL, BAND, HEIGHT, th.wall)
        side_box(room, dir, 0, CELL, BAND - 3, BAND + 3, th.trim, 0, TH + 1.5, thin)
        side_box(room, dir, 0, CELL, 0, 9, th.trim, 0, TH + 2, thin)
        return
    end
    side_box(room, dir, 0, g0, 0, BAND, th.band)
    side_box(room, dir, 0, g0, BAND, HEIGHT, th.wall)
    side_box(room, dir, g1, CELL, 0, BAND, th.band)
    side_box(room, dir, g1, CELL, BAND, HEIGHT, th.wall)
    side_box(room, dir, 0, g0 - 8, BAND - 3, BAND + 3, th.trim, 0, TH + 1.5, thin)
    side_box(room, dir, g1 + 8, CELL, BAND - 3, BAND + 3, th.trim, 0, TH + 1.5, thin)
    side_box(room, dir, 0, g0 - 8, 0, 9, th.trim, 0, TH + 2, thin)
    side_box(room, dir, g1 + 8, CELL, 0, 9, th.trim, 0, TH + 2, thin)
    side_box(room, dir, g0, g1, DOOR_H, HEIGHT, th.wall)
    side_box(room, dir, g0 - 8, g0, 0, DOOR_H + 8, th.trim, 0, TH + 3, { ghost = true })
    side_box(room, dir, g1, g1 + 8, 0, DOOR_H + 8, th.trim, 0, TH + 3, { ghost = true })
    side_box(room, dir, g0, g1, DOOR_H, DOOR_H + 8, th.trim, 0, TH + 3, { ghost = true })
    if kind == "door" and G.refuge[other.id] and not G.refuge[room.id] then
        -- A green lamp marks the way into a refuge. It stays lit when the lamps go out.
        side_box(room, dir, g1 + 18, g1 + 44, 236, 258, { 0.04, 0.42, 0.10 }, 0, TH + 4, { ghost = true, noshadow = true })
        local lx, ly = side_point(room, dir, CELL / 2, TH + 34)
        light(lx, ly, DOOR_H - 20, 7000, 380, { 0.25, 1.0, 0.40 }, nil, true)
    end
    if kind == "exit" then
        build_exit_door(room)
    elseif kind == "fake" then
        build_fake_exit(room)
    elseif link.lock ~= nil and room.id < other.id then
        local slab = side_box(room, dir, g0, g1, 0, DOOR_H, { 0.22, 0.07, 0.04 }, -6, 6)
        local plateA = side_box(room, dir, CELL / 2 + 110, CELL / 2 + 128, 100, 126, { 0.80, 0.62, 0.08 }, 6, 9, { ghost = true })
        local plateB = side_box(room, dir, CELL / 2 + 110, CELL / 2 + 128, 100, 126, { 0.80, 0.62, 0.08 }, -9, -6, { ghost = true })
        local lx, ly = side_point(room, dir, CELL / 2, 0)
        G.doors[#G.doors + 1] = { lock = link.lock, lx = lx, ly = ly, parts = { slab, plateA, plateB }, open = false }
    end
end

local SLOTS = { { -235, -235 }, { 235, 235 }, { -235, 235 }, { 235, -235 } }

local function small_table(lx, ly)
    return { box(lx - 36, ly - 36, 0, lx + 36, ly + 36, 58, WOOD), box(lx - 42, ly - 42, 58, lx + 42, ly + 42, 62, { 0.30, 0.18, 0.08 }) }
end

local function item_glow(item, color)
    local rec = light(item.lx, item.ly, 130, 9000, 320, color, nil, true)
    if rec ~= nil then
        item.props[#item.props + 1] = rec.actor
    end
end

local PROPS = {
    granola = function(item, lx, ly)
        item.base = small_table(lx, ly)
        item.props = { box(lx - 12, ly - 8, 62, lx + 12, ly + 8, 68, { 0.62, 0.46, 0.20 }, { ghost = true }) }
    end,
    canned_soup = function(item, lx, ly)
        item.base = small_table(lx, ly)
        item.props = {
            shape("cyl", lx, ly, 73, 15, 15, 22, { 0.60, 0.06, 0.05 }, { ghost = true }),
            shape("cyl", lx, ly, 85, 15.5, 15.5, 2, { 0.62, 0.62, 0.60 }, { ghost = true }),
        }
    end,
    almond_water = function(item, lx, ly)
        item.base = small_table(lx, ly)
        item.props = {
            shape("cyl", lx, ly, 76, 11, 11, 28, { 0.86, 0.90, 0.92 }, { ghost = true }),
            shape("cyl", lx, ly, 93, 6, 6, 6, { 0.10, 0.30, 0.70 }, { ghost = true }),
        }
    end,
    quiet_cot = function(item, lx, ly)
        item.base = {
            box(lx - 100, ly - 40, 34, lx + 100, ly + 40, 44, { 0.18, 0.28, 0.16 }),
            box(lx - 96, ly - 36, 0, lx - 90, ly - 30, 34, DARK, { ghost = true }),
            box(lx + 90, ly - 36, 0, lx + 96, ly - 30, 34, DARK, { ghost = true }),
            box(lx - 96, ly + 30, 0, lx - 90, ly + 36, 34, DARK, { ghost = true }),
            box(lx + 90, ly + 30, 0, lx + 96, ly + 36, 34, DARK, { ghost = true }),
            box(lx - 94, ly - 28, 44, lx - 54, ly + 28, 54, { 0.70, 0.70, 0.64 }, { ghost = true }),
        }
        item.props = {}
    end,
    buzzing_mattress = function(item, lx, ly)
        item.base = {
            box(lx - 100, ly - 50, 0, lx + 100, ly + 50, 22, { 0.62, 0.58, 0.46 }),
            box(lx - 30, ly - 20, 22, lx + 40, ly + 30, 23, { 0.40, 0.30, 0.16 }, { ghost = true }),
        }
        item.props = {}
        item.buzz = light(lx, ly, 120, 5000, 420, { 1.0, 0.9, 0.5 }, "buzz")
    end,
    vhs = function(item, lx, ly)
        item.base = small_table(lx, ly)
        item.props = {
            box(lx - 14, ly - 9, 62, lx + 14, ly + 9, 68, { 0.03, 0.03, 0.03 }, { ghost = true }),
            box(lx - 9, ly - 4, 68, lx + 9, ly + 4, 68.6, { 0.85, 0.85, 0.80 }, { ghost = true }),
        }
        item_glow(item, { 0.6, 0.7, 1.0 })
    end,
    fuse = function(item, lx, ly)
        item.base = small_table(lx, ly)
        item.props = {
            shape("cyl", lx, ly, 67, 8, 8, 26, { 0.55, 0.85, 0.90 }, { rot = { Pitch = 90, Yaw = 0, Roll = 0 }, ghost = true }),
            shape("cyl", lx - 14, ly, 67, 9, 9, 5, { 0.70, 0.55, 0.15 }, { rot = { Pitch = 90, Yaw = 0, Roll = 0 }, ghost = true }),
            shape("cyl", lx + 14, ly, 67, 9, 9, 5, { 0.70, 0.55, 0.15 }, { rot = { Pitch = 90, Yaw = 0, Roll = 0 }, ghost = true }),
        }
        item_glow(item, { 0.5, 1.0, 1.0 })
    end,
    valve = function(item, lx, ly)
        item.base = { shape("cyl", lx, ly, 55, 18, 18, 110, { 0.20, 0.20, 0.21 }) }
        item.props = {
            shape("cyl", lx, ly, 118, 58, 58, 6, { 0.08, 0.50, 0.16 }, { ghost = true }),
            shape("cyl", lx, ly, 124, 14, 14, 8, { 0.05, 0.30, 0.10 }, { ghost = true }),
        }
        item_glow(item, { 0.5, 1.0, 0.5 })
    end,
    small_key = function(item, lx, ly)
        item.base = small_table(lx, ly)
        item.props = {
            box(lx - 9, ly - 2, 62, lx + 5, ly + 2, 64, { 0.85, 0.65, 0.10 }, { ghost = true }),
            shape("cyl", lx + 9, ly, 63, 10, 10, 2, { 0.85, 0.65, 0.10 }, { ghost = true }),
        }
        item_glow(item, { 1.0, 0.85, 0.4 })
    end,
}

local function item_definition(id)
    local rel = GAME_ITEMS[id]
    if rel == nil then
        return nil
    end
    return asset(ITEM_ROOT .. rel .. "." .. rel:match("([^/]+)$") .. "_C")
end

-- The host's own backpack and pockets. A new pickup passes through one of them for an instant.
local function player_bags()
    local bags, mine = {}, ""
    pcall(function()
        mine = G.pc:GetFullName()
    end)
    for _, inventory in ipairs(FindAllOf("BETInventoryManagerComponent") or {}) do
        pcall(function()
            local name = inventory:GetFName():ToString()
            if name == "BackpackInventory" or name == "PocketsInventory" then
                -- A bag left over from the last level can have no owner any more.
                local owner = inventory:GetOwner()
                if valid(owner) and owner:GetFullName() == mine then
                    bags[#bags + 1] = { inventory = inventory, order = (name == "BackpackInventory") and 1 or 2 }
                end
            end
        end)
    end
    table.sort(bags, function(a, b)
        return a.order < b.order
    end)
    return bags
end

-- First grid cell of an inventory where an item of this definition fits.
local function free_cell(inventory, def)
    local size = inventory:GetInventorySize()
    local used = {}
    local entries = inventory.InventoryList.Entries
    for index = 1, #entries do
        local entry = entries[index]
        local sx, sy = 1, 1
        if valid(entry.ItemDef) then
            local span = entry.ItemDef:GetCDO().ItemSize
            sx, sy = span.X, span.Y
        end
        if entry.bIsRotated then
            sx, sy = sy, sx
        end
        for x = entry.Location.X, entry.Location.X + sx - 1 do
            for y = entry.Location.Y, entry.Location.Y + sy - 1 do
                used[x .. "_" .. y] = true
            end
        end
    end
    local need = def:GetCDO().ItemSize
    for y = 0, size.Y - need.Y do
        for x = 0, size.X - need.X do
            local free = true
            for dx = 0, need.X - 1 do
                for dy = 0, need.Y - 1 do
                    if used[(x + dx) .. "_" .. (y + dy)] then
                        free = false
                    end
                end
            end
            if free then
                return x, y
            end
        end
    end
    return nil
end

-- A pickup the game will accept has to come from the game: the item is added to a bag and dropped
-- again at once, which makes a pickup the loot system knows. Then it is carried to its spot.
local function drop_new_pickup(def)
    local name = def:GetFName():ToString()
    for _, bag in ipairs(player_bags()) do
        local inventory = bag.inventory
        local x, y = free_cell(inventory, def)
        if x ~= nil and inventory:AddItemDefinition(def, 1, { X = x, Y = y }) then
            local entries = inventory.InventoryList.Entries
            local at = nil
            for index = 1, #entries do
                local entry = entries[index]
                if def_name(entry.ItemDef) == name then
                    if entry.Location.X == x and entry.Location.Y == y then
                        at = index
                        break
                    end
                    at = at or index
                end
            end
            if at ~= nil and inventory:TryDropItemEntry(entries[at], 1, true) then
                -- The game reuses pickup actors, so the new one is found by where the loot list says it fell.
                local loot = G.world.GameState.LootManager.ManagedLoot.Entries
                local fell = loot[#loot].Location
                for _, pickup in ipairs(FindAllOf("BETPickup") or {}) do
                    local spot = pickup:K2_GetActorLocation()
                    if math.abs(spot.X - fell.X) < 8 and math.abs(spot.Y - fell.Y) < 8 and math.abs(spot.Z - fell.Z) < 8
                        and def_name(pickup.ItemDefinition) == name then
                        return pickup
                    end
                end
            end
            return nil
        end
    end
    return nil
end

-- A pickup of this item already lying on its spot, left there by the loop before or by a reload.
local function waiting_pickup(name, lx, ly)
    local spot = W(lx, ly, 0)
    for _, pickup in ipairs(FindAllOf("BETPickup") or {}) do
        local hit = false
        pcall(function()
            local at = pickup:K2_GetActorLocation()
            hit = math.abs(at.X - spot.X) < 45 and math.abs(at.Y - spot.Y) < 45 and math.abs(at.Z - spot.Z) < 250
                and def_name(pickup.ItemDefinition) == name
        end)
        if hit then
            return pickup
        end
    end
    return nil
end

local function place_pickup(def, lx, ly, lz, yaw)
    local name = def:GetFName():ToString()
    local actor = waiting_pickup(name, lx, ly)
    if actor == nil then
        local ok, made = pcall(drop_new_pickup, def)
        if not ok then
            log("Pickup " .. name .. " failed: " .. tostring(made))
        end
        actor = ok and made or nil
        if not valid(actor) then
            return nil
        end
        local at = W(lx, ly, lz)
        pcall(function()
            actor:K2_SetActorLocationAndRotation(at, { Pitch = 0, Yaw = yaw or 0, Roll = 0 }, false, {}, true)
        end)
        -- Item meshes hang at different heights from their actor, so rest the mesh itself on the surface.
        pcall(function()
            local o, e = {}, {}
            actor:GetActorBounds(false, o, e, false)
            local lift = at.Z - (o.Z - e.Z)
            if math.abs(lift) > 0.2 and math.abs(lift) < 60 then
                at.Z = at.Z + lift
                actor:K2_SetActorLocation(at, false, {}, true)
            end
        end)
        -- The loot list is what other players are shown, so it has to agree with where the item is.
        pcall(function()
            local loot = G.world.GameState.LootManager.ManagedLoot.Entries
            local last = loot[#loot]
            if def_name(last.ItemDefinition) == name then
                last.Location = at
            end
        end)
    end
    -- Never destroyed by us: the game owns it. Only kept out of the sweep that hides the old level.
    pcall(function()
        G.ours[actor:GetFullName()] = true
    end)
    return actor
end

-- Food, parts and the key are real game pickups. Returns false when the game item cannot be used.
local function make_game_item(item, slot)
    if GAME_ITEMS[item.id] == nil then
        return false
    end
    if not G.host then
        -- The host's pickups reach other players through the game itself.
        item.base = small_table(item.lx, item.ly)
        item.real = true
        return true
    end
    local def = item_definition(item.id)
    if def == nil then
        return false
    end
    local actor = place_pickup(def, item.lx, item.ly, 62.3, (slot * 67) % 360)
    if actor == nil then
        return false
    end
    item.base = small_table(item.lx, item.ly)
    item.real = true
    item.def = def:GetFName():ToString()
    if item.kind == "food" then
        G.food[item.def] = { hunger = item.data.hunger or 40, name = item.name }
    else
        G.partDef[item.id] = item.def
        item_glow(item, GLOWS[item.id] or { 1, 1, 1 })
    end
    return true
end

local function build_items(room)
    local contents = G.level.contents[room.id] or {}
    local cx, cy = room_center(room)
    local slot = 0
    for _, kind in ipairs({ "keys", "puzzle", "food", "rest" }) do
        for _, data in ipairs(contents[kind] or {}) do
            slot = slot + 1
            local at = SLOTS[((slot - 1) % #SLOTS) + 1]
            local item = { id = data.id, kind = kind, name = data.name, data = data, room = room.id,
                lx = cx + at[1], ly = cy + at[2], props = {}, base = {}, taken = false }
            local make = PROPS[data.id]
            if make_game_item(item, #G.items + 1) then
                G.realItems = G.realItems + 1
            elseif make ~= nil then
                make(item, item.lx, item.ly)
            else
                item.base = small_table(item.lx, item.ly)
                item.props = { box(item.lx - 8, item.ly - 8, 62, item.lx + 8, item.ly + 8, 78, { 0.8, 0.8, 0.8 }, { ghost = true }) }
            end
            G.items[#G.items + 1] = item
        end
    end
    return slot
end

local function make_chair(lx, ly)
    local chair = { lx = lx, ly = ly, parts = {} }
    local function part(ox, oy, oz, sx, sy, sz, color)
        local actor = shape("cube", lx + ox, ly + oy, oz, sx, sy, sz, color or { 0.20, 0.11, 0.05 }, { ghost = true })
        chair.parts[#chair.parts + 1] = { actor = actor, ox = ox, oy = oy, oz = oz }
    end
    -- A floor can have a crate do the creeping instead of a chair.
    if G.level.rules.creeper == "crate" then
        part(0, 0, 36, 72, 72, 72, CRATE)
        part(0, 0, 36, 76, 76, 8, shade(CRATE, 0.6))
        return chair
    end
    part(0, 0, 46, 44, 44, 6)
    part(-19, 0, 74, 6, 44, 50)
    for _, leg in ipairs({ { -19, -19 }, { 19, -19 }, { -19, 19 }, { 19, 19 } }) do
        part(leg[1], leg[2], 22, 5, 5, 44)
    end
    return chair
end

local function move_chair(chair, lx, ly)
    chair.lx, chair.ly = lx, ly
    for _, part in ipairs(chair.parts) do
        pcall(function()
            part.actor:K2_SetActorLocation(W(lx + part.ox, ly + part.oy, part.oz), false, {}, true)
        end)
    end
end

-- Furniture a level-defined theme can ask for by name. Filled in below.
local DECOR = {}

local function decorate(room, th, used)
    local cx, cy = room_center(room)
    local free = {}
    for index = #SLOTS, used + 1, -1 do
        free[#free + 1] = SLOTS[index]
    end
    if type(th.props) == "table" then
        local slot = 0
        for _, kind in ipairs(th.props) do
            local decor = DECOR[kind]
            if decor ~= nil and decor.corner then
                slot = slot + 1
                local at = free[slot]
                if at ~= nil then
                    decor.make(th, cx + at[1], cy + at[2])
                end
            elseif decor ~= nil then
                decor.make(th, cx, cy)
            end
        end
        return
    end
    local at = free[1]
    if at == nil then
        return
    end
    local lx, ly = cx + at[1], cy + at[2]
    if room.theme == "damp_office" then
        box(lx - 110, ly - 4, 0, lx + 110, ly + 4, 140, { 0.24, 0.29, 0.33 })
        box(lx + 106, ly - 110, 0, lx + 114, ly + 4, 140, { 0.24, 0.29, 0.33 })
        box(lx - 80, ly - 80, 66, lx + 60, ly - 20, 72, { 0.55, 0.50, 0.40 })
        box(lx - 76, ly - 76, 0, lx - 70, ly - 24, 66, DARK, { ghost = true })
        box(lx + 50, ly - 76, 0, lx + 56, ly - 24, 66, DARK, { ghost = true })
        box(lx - 30, ly - 62, 72, lx + 14, ly - 34, 100, { 0.10, 0.10, 0.10 }, { ghost = true })
    elseif room.theme == "pool_tile" then
        box(cx - 150, cy - 150, 0, cx + 150, cy + 150, 1.5, { 0.03, 0.30, 0.42 }, { ghost = true })
        shape("cyl", lx, ly, HEIGHT / 2, 46, 46, HEIGHT, { 0.82, 0.86, 0.86 })
    elseif room.theme == "concrete_hall" then
        box(lx - 30, ly - 30, 0, lx + 30, ly + 30, HEIGHT, { 0.28, 0.28, 0.27 })
        box(lx - 34, ly - 34, 0, lx + 34, ly + 34, 14, { 0.60, 0.50, 0.05 }, { ghost = true })
    elseif room.theme == "drop_ceiling" then
        box(lx - 100, ly - 100, HEIGHT - 3, lx + 100, ly + 100, HEIGHT - 0.5, { 0.01, 0.01, 0.01 }, { ghost = true })
        shape("cube", lx + 20, ly - 10, 6, 190, 190, 4, { 0.66, 0.64, 0.54 },
            { rot = { Pitch = 3, Yaw = 24, Roll = 2 }, ghost = true })
    end
end

local PIPE_ROT = { Pitch = 90, Yaw = 0, Roll = 0 }

-- A square concrete pillar with a painted foot.
DECOR.pillar = { corner = true, make = function(th, lx, ly)
    box(lx - 30, ly - 30, 0, lx + 30, ly + 30, HEIGHT, shade(th.wall, 0.86))
    box(lx - 34, ly - 34, 0, lx + 34, ly + 34, 14, { 0.60, 0.50, 0.05 }, { ghost = true })
end }

-- A round concrete column.
DECOR.column = { corner = true, make = function(th, lx, ly)
    shape("cyl", lx, ly, HEIGHT / 2, 64, 64, HEIGHT, shade(th.wall, 0.86))
    shape("cyl", lx, ly, 8, 78, 78, 16, shade(th.wall, 0.7), { ghost = true })
end }

-- Green growth spreading over the floor and up the foot of the walls.
DECOR.growth = { make = function(th, cx, cy)
    local leaf, dark = { 0.10, 0.30, 0.08 }, { 0.06, 0.20, 0.06 }
    local thin = { ghost = true, noshadow = true }
    local half = CELL / 2 - TH
    box(cx - half, cy - half, 0, cx - half + 210, cy - half + 150, 1.6, leaf, thin)
    box(cx + half - 180, cy + half - 240, 0, cx + half, cy + half, 1.4, dark, thin)
    box(cx - 90, cy + 60, 0, cx + 70, cy + 190, 1.2, dark, thin)
    box(cx - half, cy - half, 0, cx - half + 3, cy - half + 260, 120, leaf, thin)
    box(cx - half, cy - half, 0, cx - half + 170, cy - half + 3, 84, dark, thin)
    box(cx + half - 3, cy + half - 300, 0, cx + half, cy + half, 150, leaf, thin)
    box(cx + half - 120, cy + half - 3, 0, cx + half, cy + half, 100, dark, thin)
end }

-- Wooden crates on the floor, one stacked askew.
DECOR.crates = { corner = true, make = function(th, lx, ly)
    box(lx - 48, ly - 48, 0, lx + 48, ly + 48, 84, CRATE)
    box(lx - 50, ly - 50, 38, lx + 50, ly + 50, 46, shade(CRATE, 0.6), { ghost = true, noshadow = true })
    shape("cube", lx + 6, ly - 4, 115, 66, 66, 62, shade(CRATE, 1.12), { rot = { Pitch = 0, Yaw = 24, Roll = 0 }, ghost = true })
    box(lx + 54, ly - 30, 0, lx + 114, ly + 30, 56, shade(CRATE, 0.88))
end }

-- A metal storage shelf with crates on it.
DECOR.shelf = { corner = true, make = function(th, lx, ly)
    local steel = { 0.17, 0.18, 0.20 }
    for _, sx in ipairs({ -108, 108 }) do
        for _, sy in ipairs({ -26, 26 }) do
            box(lx + sx - 3, ly + sy - 3, 0, lx + sx + 3, ly + sy + 3, 210, steel, { noshadow = true })
        end
    end
    for _, z in ipairs({ 14, 86, 158 }) do
        box(lx - 112, ly - 30, z, lx + 112, ly + 30, z + 5, steel, { ghost = true })
    end
    box(lx - 100, ly - 26, 19, lx - 30, ly + 26, 70, CRATE)
    box(lx + 10, ly - 24, 91, lx + 78, ly + 24, 140, shade(CRATE, 0.9), { ghost = true })
    box(lx - 70, ly - 22, 163, lx - 14, ly + 22, 204, shade(CRATE, 1.1), { ghost = true })
end }

-- Two pipes under the ceiling, running the length of the room.
DECOR.pipes = { make = function(th, cx, cy)
    shape("cyl", cx, cy - 250, HEIGHT - 26, 18, 18, CELL - 2 * TH, { 0.36, 0.17, 0.08 },
        { rot = PIPE_ROT, ghost = true, noshadow = true })
    shape("cyl", cx, cy - 212, HEIGHT - 18, 10, 10, CELL - 2 * TH, { 0.30, 0.31, 0.33 },
        { rot = PIPE_ROT, ghost = true, noshadow = true })
end }

-- Small piles of debris on the floor: pieces of wood, packing material and metal.
DECOR.debris = { make = function(th, cx, cy)
    local wood, card, metal = shade(CRATE, 0.8), { 0.48, 0.40, 0.27 }, { 0.20, 0.21, 0.23 }
    local thin = { ghost = true, noshadow = true }
    local function bit(ox, oy, w, d, h, yaw, color)
        shape("cube", cx + ox, cy + oy, h / 2, w, d, h, color, { rot = { Pitch = 0, Yaw = yaw, Roll = 0 }, ghost = true, noshadow = true })
    end
    bit(-150, 40, 96, 12, 5, 18, wood)
    bit(-128, 62, 70, 10, 5, 71, wood)
    bit(-172, 78, 44, 9, 4, -33, wood)
    bit(-120, 20, 40, 34, 2, 9, card)
    bit(120, -160, 58, 46, 2, -21, card)
    bit(150, -138, 30, 30, 9, 40, card)
    bit(104, -122, 64, 7, 4, 63, metal)
    bit(170, -176, 36, 6, 3, -12, metal)
    box(cx - 190, cy + 10, 0, cx - 90, cy + 100, 0.6, shade(th.floor, 0.7), thin)
end }

-- Standing water on the floor.
DECOR.puddle = { make = function(th, cx, cy)
    local water = { th.floor[1] * 0.35, th.floor[2] * 0.40, th.floor[3] * 0.50 }
    box(cx - 170, cy - 120, 0, cx + 150, cy + 140, 1.2, water, { ghost = true, noshadow = true })
    box(cx - 60, cy + 100, 0, cx + 210, cy + 230, 1.0, water, { ghost = true, noshadow = true })
end }

-- Damp patches on the carpet and one water-stained ceiling tile, the same every run.
local function grime(room, th)
    local x0, y0 = room.x * CELL, room.y * CELL
    local seed = room.x * 7919 + room.y * 104729 + 17
    local function rnd()
        seed = (seed * 1103515245 + 12345) % 2147483648
        return (seed % 10000) / 10000
    end
    for _ = 1, 3 do
        local cx, cy = x0 + 110 + rnd() * 580, y0 + 110 + rnd() * 580
        local w, d = 70 + rnd() * 150, 60 + rnd() * 130
        box(cx - w / 2, cy - d / 2, 0, cx + w / 2, cy + d / 2, 0.5 + rnd() * 0.3, shade(th.floor, 0.72 + rnd() * 0.12),
            { ghost = true, noshadow = true })
    end
    local tx, ty = x0 + 200 * math.floor(rnd() * 4), y0 + 200 * math.floor(rnd() * 4)
    box(tx + 6, ty + 6, HEIGHT - 1.4, tx + 194, ty + 194, HEIGHT - 0.3,
        { th.ceil[1] * 0.74, th.ceil[2] * 0.66, th.ceil[3] * 0.50 }, { ghost = true, noshadow = true })
end

local function build_room(room)
    local th = theme_of(room)
    local x0, y0 = room.x * CELL, room.y * CELL
    local cx, cy = room_center(room)
    box(x0, y0, -20, x0 + CELL, y0 + CELL, 0, th.floor)
    box(x0, y0, HEIGHT, x0 + CELL, y0 + CELL, HEIGHT + 10, th.ceil)
    for _, dir in ipairs({ "E", "W", "N", "S" }) do
        build_side(room, dir, th)
    end
    box(cx - 100, cy - 50, HEIGHT - 6, cx + 100, cy + 50, HEIGHT - 1, WHITE, { ghost = true })
    room.light = light(cx, cy, HEIGHT - 70, 45000 * th.power, 1500, th.light, room.id)
    local used = build_items(room)
    decorate(room, th, used)
    grime(room, th)
end

local function build_signs()
    G.signs = {}
    local picks = {}
    for _, room in ipairs(G.level.rooms) do
        local options = neighbors(room)
        if #options >= 2 and (room.x + room.y * 3) % 2 == 0 and room.id ~= G.level.exit.room then
            picks[#picks + 1] = { room = room, dir = options[((room.x + room.y) % #options) + 1].dir }
        end
    end
    for _, pick in ipairs(picks) do
        local lx, ly = side_point(pick.room, pick.dir, CELL / 2, TH + 5)
        local px, py = side_point(pick.room, pick.dir, CELL / 2, TH + 2)
        local alongX = pick.dir == "N" or pick.dir == "S"
        box(px - (alongX and 78 or 2), py - (alongX and 2 or 78), SIGN_Z - 21, px + (alongX and 78 or 2), py + (alongX and 2 or 78),
            SIGN_Z + 21, { 0.02, 0.14, 0.05 }, { ghost = true })
        local rec = sign(lx, ly, SIGN_Z, SIDE_YAW[pick.dir], "EXIT >", 28, { 170, 255, 190 })
        if rec ~= nil then
            rec.lx, rec.ly, rec.flip, rec.last = lx, ly, 0, os.clock()
            G.signs[#G.signs + 1] = rec
        end
    end
end

local function build_ceiling_grid()
    local wx, wy = G.w * CELL, G.h * CELL
    local dark = { 0.16, 0.15, 0.12 }
    for i = 1, wx / 200 - 1 do
        if i % 4 ~= 0 then
            box(i * 200 - 2, 0, HEIGHT - 2, i * 200 + 2, wy, HEIGHT, dark, { ghost = true, noshadow = true })
        end
    end
    for i = 1, wy / 200 - 1 do
        if i % 4 ~= 0 then
            box(0, i * 200 - 2, HEIGHT - 2, wx, i * 200 + 2, HEIGHT, dark, { ghost = true, noshadow = true })
        end
    end
end

local function map_bounds()
    return { x0 = -FAKE_LEN - 300, x1 = G.epi.cx + EPI_HALF + 500, y0 = -300, y1 = G.h * CELL + 300, z0 = -300, z1 = HEIGHT + 300 }
end

local function move_nav_bounds()
    local vols = FindAllOf("NavMeshBoundsVolume") or {}
    local b = map_bounds()
    local cx, cy = (b.x0 + b.x1) / 2, (b.y0 + b.y1) / 2
    local centre = W(cx, cy, 150)
    local pick, pickScore = nil, nil
    for _, vol in ipairs(vols) do
        local o, e = {}, {}
        pcall(function()
            vol:GetActorBounds(false, o, e, false)
        end)
        if o.X ~= nil then
            local near = math.abs(o.X - centre.X) + math.abs(o.Y - centre.Y) + math.abs(o.Z - centre.Z)
            local score = (near < 30000) and -1e12 or (o.Z + (e.X or 0) * 0.001)
            if pickScore == nil or score < pickScore then
                pick, pickScore = vol, score
            end
        end
    end
    if pick == nil then
        log("No navigation volume to move. The monster will stand still.")
        return false
    end
    local ok, err = pcall(function()
        pick.BrushComponent:SetMobility(2)
        pick:K2_SetActorLocation(centre, false, {}, true)
        pick:SetActorScale3D({ X = (b.x1 - b.x0) / 200, Y = (b.y1 - b.y0) / 200, Z = 3 })
        FindFirstOf("NavigationSystemV1"):OnNavigationBoundsUpdated(pick)
    end)
    if not ok then
        log("Navigation move failed " .. tostring(err))
    end
    return ok
end

local function spawn_monster()
    local class = asset(MONSTER_CLASS)
    local spec = G.level.monsters and G.level.monsters[1]
    if class == nil or spec == nil then
        log("Skin Stealer class is missing. No monster this run.")
        return
    end
    local home = G.rooms[spec.patrol[1]]
    local lx, ly = room_center(home)
    local actor = nil
    pcall(function()
        actor = G.world:SpawnActor(class, W(lx, ly, 130), ZERO)
    end)
    if valid(actor) then
        track(actor)
        G.monster = actor
        G.monsterHome = home
        G.monsterArmed = false
        G.brainOff = false
        log("Skin Stealer walks " .. home.id)
    end
end

-- Without its ability set the Skin Stealer reaches you, starts a grab and freezes forever.
local function arm_monster()
    local set = asset(MONSTER_ABILITIES)
    if set == nil then
        log("Skin Stealer ability set is missing. It cannot kill this run.")
        return
    end
    local ok, err = pcall(function()
        local asc = G.monster.AbilitySystemComponent
        if #asc.ActivatableAbilities.Items == 0 then
            set:K2_GiveToAbilitySystem(asc)
        end
        log("Skin Stealer has " .. #asc.ActivatableAbilities.Items .. " abilities")
    end)
    if not ok then
        log("Skin Stealer abilities failed " .. tostring(err))
    end
end

local function level_manager()
    local manager = nil
    pcall(function()
        manager = G.world.GameState.LevelManager
    end)
    return valid(manager) and manager or nil
end

local function level_is_dark()
    local dark = false
    pcall(function()
        local tags = G.world.GameState.LevelManager.LevelTags.GameplayTags
        for index = 1, #tags do
            if tags[index].TagName:ToString() == BLACKOUT_TAG then
                dark = true
            end
        end
    end)
    return dark
end

-- The Skin Stealer only chases while the level carries the game's own lights-out tag.
local function set_level_dark(on)
    local manager = level_manager()
    if manager == nil then
        return
    end
    pcall(function()
        local tags = manager.LevelTags.GameplayTags
        local at, spare, other, seen = nil, nil, nil, {}
        for index = 1, #tags do
            local name = tags[index].TagName:ToString()
            if name == BLACKOUT_TAG then
                at = at or index
            elseif seen[name] then
                spare = spare or index
            else
                seen[name] = true
                other = other or index
            end
        end
        if on and at == nil then
            local source = nil
            local events = manager.RandomEvents
            for i = 1, #events do
                local list = events[i].EventTags.GameplayTags
                for j = 1, #list do
                    if list[j].TagName:ToString() == BLACKOUT_TAG then
                        source = list[j]
                    end
                end
            end
            if source ~= nil then
                tags[spare or (#tags + 1)] = source
            end
        elseif not on and at ~= nil and other ~= nil then
            -- The list cannot shrink from here, so the slot goes back to a tag that is already in it.
            tags[at] = tags[other]
        end
    end)
end

-- What the game itself tells the level, the monster and its controller when the lights change.
local function announce_lights(on)
    local targets = { level_manager() }
    if valid(G.monster) then
        targets[#targets + 1] = G.monster
        pcall(function()
            targets[#targets + 1] = G.monster:GetController()
        end)
    end
    for _, target in ipairs(targets) do
        pcall(function()
            target:OnToggleLights(on)
        end)
    end
end

local function start_hunt(seconds, line)
    if G.hunt ~= nil or G.zone ~= "room" then
        return false
    end
    G.hunt = { t0 = os.clock(), untilT = os.clock() + seconds }
    set_lights(DARK_K)
    sfx("knock")
    if G.host then
        announce_lights(false)
    end
    say(line or L("huntStart", "The lights are out. It hunts in the dark. Keep your flashlight on it."), 5)
    return true
end

local function end_hunt(quiet)
    if G.hunt == nil then
        return
    end
    local native = G.hunt.native
    G.hunt = nil
    G.nextHunt = os.clock() + 120 + math.random() * 80
    if G.host and not native then
        set_level_dark(false)
        announce_lights(true)
    end
    set_lights(1)
    if not quiet then
        sfx("hum", 0.8)
        say(L("huntEnd", "The lamps come back. It lets go of the dark."), 4)
    end
end

local function monster_to(lx, ly)
    if not valid(G.monster) then
        return
    end
    pcall(function()
        G.monster:K2_SetActorLocation(W(lx, ly, 130), false, {}, true)
    end)
end

-- Hide whatever the original level put where the generated floor now is.
local function hide_original()
    local b = map_bounds()
    local lo, hi = W(b.x0, b.y0, b.z0), W(b.x1, b.y1, b.z1)
    local keep = { "Survivor", "SkinStealer", "Controller", "PlayerCamera", "GameMode", "GameState", "PlayerState",
        "Manager", "Volume", "NavMesh", "Recast", "Navigation", "WorldSettings", "PostProcess", "HUD", "GameSession" }
    local hidden, seen = 0, 0
    for _, actor in ipairs(FindAllOf("Actor") or {}) do
        local name = ""
        pcall(function()
            name = actor:GetFullName()
        end)
        local spare = G.ours[name] == true
        if not spare then
            for _, word in ipairs(keep) do
                if name:find(word, 1, true) then
                    spare = true
                    break
                end
            end
        end
        if not spare then
            seen = seen + 1
            local o, e = {}, {}
            pcall(function()
                actor:GetActorBounds(false, o, e, false)
            end)
            if o.X ~= nil and e.X ~= nil
                and o.X + e.X >= lo.X and o.X - e.X <= hi.X
                and o.Y + e.Y >= lo.Y and o.Y - e.Y <= hi.Y
                and o.Z + e.Z >= lo.Z and o.Z - e.Z <= hi.Z then
                pcall(function()
                    actor:SetActorHiddenInGame(true)
                    actor:SetActorEnableCollision(false)
                    actor:SetActorScale3D({ X = 0.001, Y = 0.001, Z = 0.001 })
                end)
                hidden = hidden + 1
            end
        end
    end
    log("Cleared " .. hidden .. " of " .. seen .. " original actors from the floor")
    -- The shaft and the old level are built from large shared meshes whose bounds do not say
    -- where they are drawn, so every mesh that is not ours is switched off as well.
    for _, className in ipairs({ "StaticMeshComponent", "InstancedStaticMeshComponent",
        "HierarchicalInstancedStaticMeshComponent", "SplineMeshComponent" }) do
        local list = FindAllOf(className) or {}
        local off = 0
        for _, component in ipairs(list) do
            local ownerName = ""
            pcall(function()
                local owner = component:GetOwner()
                if valid(owner) then
                    ownerName = owner:GetFullName() or ""
                end
            end)
            if not G.ours[ownerName] and not ownerName:find("Survivor", 1, true) and not ownerName:find("SkinStealer", 1, true) then
                local ok = pcall(function()
                    component:SetHiddenInGame(true, true)
                    component:SetVisibility(false, true)
                    component:SetWorldScale3D({ X = 0.001, Y = 0.001, Z = 0.001 })
                end)
                if ok then
                    off = off + 1
                end
            end
        end
        log(className .. " switched off " .. off .. " of " .. #list)
    end
end
H.hide_original = hide_original

local function hud_block(name, ax, ay, alignX, alignY, size, justify)
    local text = StaticConstructObject(G.cls.textblock, HUD.tree, FName(name .. "_" .. HUD.serial))
    local slot = HUD.canvas:AddChildToCanvas(text)
    slot:SetAnchors({ Minimum = { X = ax, Y = ay }, Maximum = { X = ax, Y = ay } })
    slot:SetAlignment({ X = alignX, Y = alignY })
    slot:SetAutoSize(true)
    pcall(function()
        local font = text.Font
        font.Size = size
        if valid(HUD.font) then
            font.FontObject = HUD.font
        end
        text:SetFont(font)
    end)
    pcall(function()
        text:SetShadowOffset({ X = 2, Y = 2 })
        text:SetShadowColorAndOpacity({ R = 0, G = 0, B = 0, A = 0.9 })
    end)
    pcall(function()
        text:SetJustification(justify or 0)
    end)
    text:SetText(FText(""))
    return text
end

local function ensure_hud()
    local inView = false
    if HUD ~= nil and valid(HUD.widget) then
        pcall(function()
            inView = HUD.widget:IsInViewport()
        end)
    end
    if inView then
        return
    end
    for _, old in ipairs(FindAllOf("UserWidget") or {}) do
        pcall(function()
            if old:GetFName():ToString():find("CBR_Hud_", 1, true) then
                old:RemoveFromParent()
            end
        end)
    end
    local serial = (rawget(_G, "CBR_HUD_SERIAL") or 0) + 1
    rawset(_G, "CBR_HUD_SERIAL", serial)
    HUD = { serial = serial, shown = {} }
    rawset(_G, "CBR_HUD", HUD)
    local instance = FindFirstOf("GameInstance")
    HUD.widget = StaticConstructObject(asset("/Script/UMG.UserWidget"), instance, FName("CBR_Hud_" .. serial))
    HUD.tree = StaticConstructObject(asset("/Script/UMG.WidgetTree"), HUD.widget, FName("CBR_Tree_" .. serial))
    HUD.widget.WidgetTree = HUD.tree
    HUD.canvas = StaticConstructObject(asset("/Script/UMG.CanvasPanel"), HUD.tree, FName("CBR_Canvas_" .. serial))
    HUD.tree.RootWidget = HUD.canvas
    HUD.font = asset("/Game/Slate/VCR_OSD_MONO_RU_Font.VCR_OSD_MONO_RU_Font")
    HUD.status = hud_block("CBR_Status", 0.03, 0.06, 0, 0, 17, 0)
    HUD.prompt = hud_block("CBR_Prompt", 0.5, 0.78, 0.5, 0.5, 20, 1)
    HUD.sub = hud_block("CBR_Sub", 0.5, 0.87, 0.5, 0.5, 23, 1)
    HUD.big = hud_block("CBR_Big", 0.5, 0.36, 0.5, 0.5, 58, 1)
    HUD.widget:AddToViewport(99)
end

local function hud_set(which, text)
    if HUD == nil or HUD.shown[which] == text or not valid(HUD[which]) then
        return
    end
    HUD.shown[which] = text
    pcall(function()
        HUD[which]:SetText(FText(text))
    end)
end

-- Darker exposure, heavier vignette and a little less colour on each player's own camera.
local function mood()
    for _, pawn in ipairs(survivors()) do
        pcall(function()
            local cam = pawn.CameraComponent
            if not valid(cam) then
                return
            end
            local pp = cam.PostProcessSettings
            pp.bOverride_AutoExposureBias = true
            pp.AutoExposureBias = -1.2
            pp.bOverride_VignetteIntensity = true
            pp.VignetteIntensity = 0.7
            pp.bOverride_ColorSaturation = true
            pp.ColorSaturation = { X = 0.84, Y = 0.84, Z = 0.84, W = 1.0 }
            cam.PostProcessBlendWeight = 1.0
        end)
    end
end

local function refresh_exit_lamps()
    if G.exit == nil then
        return
    end
    for id, lamp in pairs(G.exit.lamps) do
        if valid(lamp) then
            paint(lamp, (G.have[id] or G.exit.state ~= "shut") and GREEN or RED)
        end
    end
end

local function collapse()
    if G.busy then
        return
    end
    G.busy = true
    fade(0, 1, 0.8, { 0, 0, 0 }, true)
    after(1.2, function()
        local lx, ly = room_center(G.rooms[G.level.start])
        teleport(lx, ly, 0)
        G.hunger, G.stamina = 60, 60
        G.stalkPause = os.clock() + 30
        if valid(G.monster) and G.monsterHome ~= nil then
            monster_to(room_center(G.monsterHome))
        end
        G.roomId = G.level.start
        fade(1, 0, 2.0, { 0, 0, 0 }, false)
        say(L("wake", "You wake up where the elevator was. It is still not there."), 5)
        G.busy = false
    end)
end

-- Taking a part wakes the dark for a few seconds.
local function take_part_scare(item)
    sfx("knock")
    blackout(1.2, function()
        start_hunt(11, L("huntTaken", "Taking it woke the dark. It is coming. Keep your flashlight on it."))
    end)
end

local function each_inventory(fn)
    -- Bags, pockets and the equipment slots of every player are all this one kind of component,
    -- and they hang on the player's controller. After a restart the last level's controllers can
    -- linger for up to a minute with everything the dead players carried, and they report this level
    -- as theirs. So only the controllers of players who are in this level count.
    local live, known = {}, false
    pcall(function()
        local players = G.world.GameState.PlayerArray
        for index = 1, #players do
            local player = players[index]
            if valid(player) then
                local owner = player:GetOwner()
                if valid(owner) then
                    live[owner:GetAddress()] = true
                    known = true
                end
            end
        end
    end)
    for _, inventory in ipairs(FindAllOf("BETInventoryManagerComponent") or {}) do
        local here = not known
        if known then
            pcall(function()
                local owner = inventory:GetOwner()
                here = valid(owner) and live[owner:GetAddress()] == true
            end)
        end
        if here then
            fn(inventory)
        end
    end
end

-- What every player carries, counted by item definition.
local function scan_carried()
    local counts = {}
    each_inventory(function(inventory)
        pcall(function()
            local entries = inventory.InventoryList.Entries
            for index = 1, #entries do
                local entry = entries[index]
                local name = def_name(entry.ItemDef)
                if name ~= nil then
                    local stack = tonumber(entry.StackCount) or 1
                    counts[name] = (counts[name] or 0) + math.max(1, stack)
                end
            end
        end)
    end)
    return counts
end

-- Pickups lying on our floor: how many of each, and where.
local function scan_floor()
    local counts, lying = {}, {}
    for _, pickup in ipairs(FindAllOf("BETPickup") or {}) do
        pcall(function()
            local at = pickup:K2_GetActorLocation()
            if math.abs(at.Z - G.O.z) < 900 then
                local name = def_name(pickup.ItemDefinition)
                if name ~= nil then
                    counts[name] = (counts[name] or 0) + 1
                    lying[#lying + 1] = { name = name, x = at.X - G.O.x, y = at.Y - G.O.y }
                end
            end
        end)
    end
    return counts, lying
end

-- The group has a part when somebody carries it, or took it the old way with F9.
local function refresh_have()
    local changed = false
    for _, id in ipairs(G.partIds) do
        local owned = G.picked[id] == true
        local def = G.partDef[id]
        if not owned and def ~= nil then
            owned = (G.carried[def] or 0) - (G.spent[id] or 0) > 0
        end
        if owned ~= (G.have[id] == true) then
            G.have[id] = owned
            changed = true
        end
    end
    if changed then
        refresh_exit_lamps()
        H.broadcast()
    end
end

-- The door keeps what opened it: one of each part leaves the group's inventory.
local function spend_parts()
    if not G.host then
        return
    end
    local want = {}
    for _, id in ipairs(G.level.exit.requires) do
        if G.partDef[id] ~= nil then
            want[G.partDef[id]] = true
        end
    end
    each_inventory(function(inventory)
        pcall(function()
            local entries = inventory.InventoryList.Entries
            for index = #entries, 1, -1 do
                local entry = entries[index]
                local name = def_name(entry.ItemDef)
                if want[name] and inventory:TryConsumeItemEntry(entry, 1, false) then
                    want[name] = nil
                end
            end
        end)
    end)
end

local function update_items(t)
    if not G.host or G.realItems == 0 or t - (G.itemTick or 0) < 0.5 then
        return
    end
    G.itemTick = t
    G.carried = scan_carried()
    local floor, lying = scan_floor()
    -- The game recycles pickup actors, so an item counts as taken once nothing of its kind lies on its spot.
    for _, item in ipairs(G.items) do
        if item.def ~= nil and not item.taken then
            local there = false
            for _, rec in ipairs(lying) do
                if rec.name == item.def and math.abs(rec.x - item.lx) < 45 and math.abs(rec.y - item.ly) < 45 then
                    there = true
                    break
                end
            end
            item.missing = there and 0 or ((item.missing or 0) + 1)
            if item.missing >= 2 then
                item.taken = true
                for _, prop in ipairs(item.props) do
                    destroy(prop)
                end
                if item.kind == "puzzle" then
                    take_part_scare(item)
                    after(3.5, function()
                        say(item.data.clue or ("You have the " .. item.name:lower() .. "."), 5)
                    end)
                elseif item.kind == "keys" then
                    say(L("keyTaken", "A {item}. It is warm.", { item = item.name:lower() }), 4)
                end
            end
        end
    end
    -- Food that left every pocket without landing on the floor was eaten.
    for def, food in pairs(G.food) do
        local total = (G.carried[def] or 0) + (floor[def] or 0)
        local known = G.foodTotal[def]
        if known == nil or total >= known then
            G.foodTotal[def], G.foodLow[def] = total, nil
        else
            G.foodLow[def] = (G.foodLow[def] or 0) + 1
            if G.foodLow[def] >= 2 then
                G.hunger = math.min(100, G.hunger + food.hunger * (known - total))
                G.foodTotal[def], G.foodLow[def] = total, nil
                say(L("eat", "You eat the {item}. It tastes like the hum sounds.", { item = food.name:lower() }), 4)
                H.broadcast()
            end
        end
    end
    refresh_have()
end

local function words(list)
    if #list < 2 then
        return list[1] or ""
    end
    return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

-- What the group still has to do, in order. The same list feeds the game's own objective panel,
-- which shows three one-line rows without scrolling, so each line stays under 27 characters.
-- Without a state it is the list of a floor nobody has touched yet.
local function objective_rows(level, s)
    s = s or {}
    local have, unlocked = s.have or {}, s.unlocked or {}
    local need = level.exit.requires
    local got, names, required = 0, {}, {}
    for _, id in ipairs(need) do
        required[id] = true
        names[#names + 1] = (PART_LABEL[id] or id):lower()
        if have[id] then
            got = got + 1
        end
    end
    local rows = { { text = LT(level, "objectiveParts", "Find " .. words(names)), amount = #need,
        progress = s.opened and #need or got } }
    local listed = {}
    for _, link in ipairs(level.links) do
        local id = link.lock
        if id ~= nil and not required[id] and not listed[id] then
            listed[id] = true
            local label = id:gsub("_", " ")
            -- A key that has opened its door stays found, even when it is dropped afterwards.
            local found = s.opened or have[id] or unlocked[id]
            rows[#rows + 1] = { text = LT(level, "objectiveKey", "Find the " .. label), amount = 1,
                progress = found and 1 or 0 }
        end
    end
    rows[#rows + 1] = { text = LT(level, "objectiveExit", "Leave through MAINTENANCE"), amount = 1,
        progress = s.escaped and 1 or 0 }
    return rows
end

-- The overview, the HUD popups and the spectator view all read the game state's objective list,
-- and the game sends that list to every player. So the floor's objectives are written into it.
-- Returns how many lines of the game's own it replaced, or nil when the list was already right.
local function write_objectives(state, rows)
    local list = state.CurrentObjectives
    local same = #list == #rows
    if same then
        for index, row in ipairs(rows) do
            local entry = list[index]
            if entry.ObjectiveType ~= 0 or entry.ObjectiveAmount ~= row.amount or entry.ObjectiveProgress ~= row.progress
                or (entry.bIsComplete == true) ~= (row.progress >= row.amount)
                or entry.ObjectiveDescription:ToString() ~= row.text then
                same = false
                break
            end
        end
    end
    if same then
        return nil
    end
    local foreign = 0
    for index = 1, #list do
        if list[index].ObjectiveType ~= 0 then
            foreign = foreign + 1
        end
    end
    -- A tag no pickup or recording reports, so the game never advances these lines by itself.
    local quiet = nil
    pcall(function()
        local tags = state.LevelManager.LevelTags.GameplayTags
        for index = 1, #tags do
            if tags[index].TagName:ToString():find("Level.", 1, true) == 1 then
                quiet = tags[index]
            end
        end
    end)
    if #list > #rows then
        -- The list cannot lose single lines from here, so a longer one is cleared and written again.
        list:Empty()
    end
    for index, row in ipairs(rows) do
        if index > #list then
            list[index] = { ObjectiveType = 0, ObjectiveAmount = row.amount }
        end
        local entry = list[index]
        entry.ObjectiveType = 0
        entry.ObjectiveDescription = FText(row.text)
        entry.ObjectiveAmount = row.amount
        entry.ObjectiveProgress = row.progress
        entry.bIsComplete = row.progress >= row.amount
        entry.bScalesWithPlayers = false
        entry.bDisplayAsPercentage = false
        if quiet ~= nil then
            entry.ObjectiveContext.GameplayTags[1] = quiet
        end
    end
    -- What the game runs when the list changes: refreshes the panels and shows new or finished lines.
    state:OnRep_CurrentObjectives()
    return foreign
end

local function update_objectives(t)
    if t - (G.objectiveTick or 0) < 0.1 then
        return
    end
    G.objectiveTick = t
    local unlocked = {}
    for _, door in ipairs(G.doors) do
        if door.lock ~= nil and door.open then
            unlocked[door.lock] = true
        end
    end
    local foreign = write_objectives(G.world.GameState, objective_rows(G.level, {
        have = G.have,
        unlocked = unlocked,
        opened = G.exit ~= nil and G.exit.state ~= "shut",
        escaped = G.escaped == true,
    }))
    if foreign ~= nil and foreign > 0 then
        log("Objectives: replaced " .. foreign .. " of Level 0's own")
    end
end

-- A fresh level picks objectives from Level 0's own pool long before the elevator stops and the floor
-- is built. For that stretch the host swaps them as soon as they appear, so nobody is sent after VHS tapes.
local EARLY_FOR = 45
local earlyUntil, earlyTick = 0, 0

local function early_objectives(t)
    if t > earlyUntil or t - earlyTick < 0.25 then
        return
    end
    earlyTick = t
    local level = ctx.level()
    if level == nil then
        return
    end
    for _, state in ipairs(FindAllOf("MultiplayerGameState") or {}) do
        pcall(function()
            -- The level that was just left is still around for a moment. Its state says so itself,
            -- and nothing else about it is looked at.
            if not valid(state) or state.MatchState:ToString() == "LeavingMap" then
                return
            end
            if not state:GetFullName():find("L_Level_0.", 1, true) then
                return
            end
            local world = state:GetWorld()
            if not valid(world) or not valid(world.AuthorityGameMode) then
                return
            end
            local foreign = write_objectives(state, objective_rows(level))
            if foreign ~= nil then
                log("Objectives: written before the build, replaced " .. foreign .. " of Level 0's own")
            end
        end)
    end
end

local function hint_now(death)
    if death then
        return L("tipDeath", "It only hunts while the lights are out")
    end
    local opened = G.exit ~= nil and G.exit.state ~= "shut"
    if opened then
        return L("tipHall", "Walk the hall. Do not look back.")
    end
    local missing, required = 0, {}
    for _, id in ipairs(G.level.exit.requires) do
        required[id] = true
        if not G.have[id] then
            missing = missing + 1
        end
    end
    if missing > 0 then
        return L("tipParts", "The parts lie on tables in the rooms")
    end
    for _, id in ipairs(G.partIds) do
        if not required[id] and not G.have[id] then
            return "The " .. id:gsub("_", " ") .. " opens the locked room"
        end
    end
    return "F9 at the " .. L("exitSign", "MAINTENANCE") .. " door opens it"
end

-- The floor's own HUD sits on top of everything, so it steps aside while the game's menu is open.
local function update_menu_cover(t)
    if HUD == nil or not valid(HUD.widget) then
        return
    end
    if not valid(G.pauseMenu) and t - (G.pauseMenuAt or 0) > 3 then
        G.pauseMenuAt = t
        -- After a restart the last level's HUD lingers. The one that belongs to this player's controller is the live one.
        local mine, any = nil, nil
        for _, hud in ipairs(FindAllOf("BP_HudWidget_C") or {}) do
            pcall(function()
                if hud:GetFullName():find("/Engine/Transient", 1, true) then
                    any = hud
                    if hud:GetOwningPlayer():GetAddress() == G.pc:GetAddress() then
                        mine = hud
                    end
                end
            end)
        end
        local hud = mine or any
        if hud ~= nil then
            G.pauseMenu = hud.PauseMenu
        end
    end
    local open = valid(G.pauseMenu) and G.pauseMenu:IsActivated() == true
    if open ~= G.menuOpen then
        G.menuOpen = open
        -- 1 is collapsed, 3 is drawn but never in the way of the mouse.
        HUD.widget:SetVisibility(open and 1 or 3)
    end
end

-- The overview and the death screen show a Level 0 tip that is wrong for this floor. Each player sees ours instead.
local function update_hints(t)
    if G.hints == nil or t - G.hintsAt > 3 then
        G.hints, G.hintsAt = {}, t
        for _, widget in ipairs(FindAllOf("BETLoadingScreenHintWidget") or {}) do
            local name = widget:GetFullName()
            if name:find("/Engine/Transient", 1, true) then
                G.hints[#G.hints + 1] = { widget = widget, death = name:find("DeathScreen", 1, true) ~= nil }
            end
        end
    end
    for _, hint in ipairs(G.hints) do
        if valid(hint.widget) then
            local want = hint_now(hint.death)
            local block = hint.widget.HintTextBlock
            if valid(block) and block:GetText():ToString() ~= want then
                block:SetText(FText(want))
            end
        end
    end
end

local function open_exit()
    local door = G.exit
    door.state = "opening"
    sfx("unlock")
    say(L("doorOpen", "The door drinks the light."), 4)
    spend_parts()
    refresh_exit_lamps()
    local room = G.rooms[G.level.exit.room]
    local steps = 12
    for step = 1, steps do
        after(step * 0.2, function()
            if room.light ~= nil then
                room.light.k = math.max(0.12, 1 - step / steps)
                apply_light(room.light)
            end
        end)
    end
    slide(door.slab, door.lx, door.ly, DOOR_H / 2, DOOR_H / 2 + DOOR_H + 20, 2.6, function()
        door.state = "open"
        hall_refresh()
    end)
end

local function target_now()
    local best, bestD = nil, USE_RANGE
    for _, item in ipairs(G.items) do
        local usable = not item.taken and not item.real
        if usable then
            local d = dist_to(item.lx, item.ly)
            if d < bestD then
                best, bestD = { kind = "item", item = item }, d
            end
        end
    end
    if G.exit ~= nil and G.exit.state == "shut" then
        local d = dist_to(G.exit.lx - 60, G.exit.ly)
        if d < bestD then
            best, bestD = { kind = "exit" }, d
        end
    end
    return best
end

local function prompt_for(target)
    if target == nil then
        for _, door in ipairs(G.doors) do
            if not door.open and dist_to(door.lx, door.ly) < 260 and not G.have[door.lock] then
                return "LOCKED. IT WANTS A SMALL KEY."
            end
        end
        return ""
    end
    if target.kind == "exit" then
        return "[F9] TRY THE " .. L("exitSign", "MAINTENANCE") .. " DOOR"
    end
    local item = target.item
    if item.kind == "food" then
        return "[F9] EAT: " .. item.name:upper()
    elseif item.kind == "rest" then
        return "[F9] REST: " .. item.name:upper()
    end
    return "[F9] TAKE: " .. item.name:upper()
end

local function take_item(item)
    item.taken = true
    for _, prop in ipairs(item.props) do
        destroy(prop)
    end
    if item.kind == "food" then
        G.consumed[item.id] = true
        G.hunger = math.min(100, G.hunger + (item.data.hunger or 40))
        say(L("eat", "You eat the {item}. It tastes like the hum sounds.", { item = item.name:lower() }), 4)
    elseif item.kind == "rest" then
        G.consumed[item.id] = true
        G.stamina = math.min(100, G.stamina + (item.data.stamina or 50))
        fade(0, 1, 0.5, { 0, 0, 0 }, true)
        after(1.1, function()
            fade(1, 0, 1.2, { 0, 0, 0 }, false)
        end)
        if item.data.callsMonster then
            say(L("restLoud", "The springs sing. Somewhere in the hall, something turns its head."), 5)
            after(1.0, function()
                local here = G.rooms[item.room]
                local n = neighbors(here)[1]
                if n ~= nil and not G.god then
                    monster_to(room_center(n.room))
                end
            end)
        else
            say(L("restQuiet", "You close your eyes. Nothing moves that you can hear."), 4)
        end
    elseif item.kind == "puzzle" then
        G.picked[item.id] = true
        refresh_have()
        take_part_scare(item)
        after(3.5, function()
            say(item.data.clue or ("You have the " .. item.name:lower() .. "."), 5)
        end)
    else
        G.picked[item.id] = true
        refresh_have()
        say(L("keyTaken", "A {item}. It is warm.", { item = item.name:lower() }), 4)
    end
    H.broadcast()
end

-- Test shortcut for scripted walks, which cannot press the game's pickup key:
-- counts the game item on the table in front of the player as taken. The pickup itself stays.
function H.take()
    if G == nil or not G.built or G.busy then
        return false
    end
    for _, item in ipairs(G.items) do
        if item.real and not item.taken and dist_to(item.lx, item.ly) < USE_RANGE then
            take_item(item)
            return true
        end
    end
    return false
end

function H.use()
    if G == nil or not G.built or G.busy or not valid(G.pawn) then
        return
    end
    local target = target_now()
    if target == nil then
        local room = G.rooms[G.roomId or ""]
        if room ~= nil and G.zone == "room" then
            say(room.description, 4, "room")
        end
        return
    end
    if target.kind == "exit" then
        local missing = {}
        for _, id in ipairs(G.level.exit.requires) do
            if not G.have[id] then
                missing[#missing + 1] = PART_LABEL[id] or id:upper()
            end
        end
        if #missing > 0 then
            sfx("knock", 0.6)
            say(L("doorShut", "The door stays shut. Missing: {parts}.", { parts = table.concat(missing, ", ") }), 4)
        else
            open_exit()
        end
        return
    end
    take_item(target.item)
end

local function enter_room(room, t)
    local prev = G.roomId
    G.roomId = room.id
    G.roomSince = t
    G.whispered = false
    local first = not G.visited[room.id]
    if first then
        G.visited[room.id] = true
        G.visitedCount = G.visitedCount + 1
        G.glitch = (G.visitedCount == 7)
    else
        G.glitch = false
    end
    if prev ~= nil and G.host and not G.god then
        local cost = first and G.level.rules.moveHunger or 5
        G.hunger = math.max(0, G.hunger - cost)
        G.stamina = math.max(0, G.stamina - (first and G.level.rules.moveStamina or 5))
    end
    if first and prev ~= nil then
        say(room.description, 5, "room")
    end
    local seal = G.seal
    if seal.state == "armed" and prev == G.level.start and room.id ~= G.level.start then
        local start = G.rooms[G.level.start]
        for dir, d in pairs(DIRS) do
            if start.x + d[1] == room.x and start.y + d[2] == room.y then
                seal.state, seal.dir = "pending", dir
                seal.lx, seal.ly = side_point(start, dir, CELL / 2, 0)
            end
        end
    elseif seal.state == "pending" and room.id == G.level.start then
        seal.state = "armed"
    end
    if G.hunger <= 0 or G.stamina <= 0 then
        say(L("collapse", "Your legs stop answering."), 3)
        collapse()
    elseif G.hunger <= 30 and not G.warnedHunger then
        G.warnedHunger = true
        say(L("hungry", "Your stomach turns. Find something to eat."), 4)
    elseif G.stamina <= 30 and not G.warnedStamina then
        G.warnedStamina = true
        say(L("tired", "You are slowing down. Find somewhere to rest."), 4)
    end
    if G.hunger > 45 then
        G.warnedHunger = false
    end
    if G.stamina > 45 then
        G.warnedStamina = false
    end
    H.broadcast()
end

local function update_zone(t)
    local lx, ly = G.px, G.py
    local zone, room = "void", nil
    if lx >= 0 and ly >= 0 and lx < G.w * CELL and ly < G.h * CELL then
        room = G.grid[math.floor(lx / CELL) .. "_" .. math.floor(ly / CELL)]
        zone = "room"
    elseif lx >= G.hall.x0 and lx <= G.hall.xe and math.abs(ly - G.hall.yc) <= HALL_HALF + 20 then
        zone = "hall"
    elseif lx < 0 and lx > -FAKE_LEN - 20 and math.abs(ly - G.fake.yc) <= DOOR_W / 2 + 20 then
        zone = "fake"
    elseif math.abs(lx - G.epi.cx) <= EPI_HALF + 260 and math.abs(ly - G.epi.cy) <= EPI_HALF + 20 then
        zone = "epi"
    end
    G.zone = zone
    if room ~= nil and room.id ~= G.roomId then
        enter_room(room, t)
    end
    if G.pz < -600 and not G.busy then
        local back = G.rooms[G.roomId or G.level.start] or G.rooms[G.level.start]
        teleport(room_center(back))
    end
end

local function update_seal(t)
    local seal = G.seal
    if seal.state == "pending" then
        if G.roomId ~= G.level.start and dist_to(seal.lx, seal.ly) > 230 and not in_view(seal.lx, seal.ly, 120, 0.15) then
            local start = G.rooms[G.level.start]
            local d = DIRS[seal.dir]
            seal.parts = plug(start, seal.dir, G.grid[(start.x + d[1]) .. "_" .. (start.y + d[2])])
            seal.state, seal.t, seal.noticed = "sealed", t, false
        end
    elseif seal.state == "sealed" then
        if not seal.noticed and dist_to(seal.lx, seal.ly) < 760 and in_view(seal.lx, seal.ly, 120, 0.75) then
            seal.noticed = true
            sfx("knock", 0.7)
            say(L("sealed", "That was a doorway a moment ago."), 4)
        end
        local start = G.rooms[G.level.start]
        local here = G.rooms[G.roomId or ""]
        local far = here ~= nil and math.max(math.abs(here.x - start.x), math.abs(here.y - start.y)) >= 2
        if (far or t - seal.t > 45) and dist_to(seal.lx, seal.ly) > 500 and not in_view(seal.lx, seal.ly, 120, 0.15) then
            for _, part in ipairs(seal.parts or {}) do
                destroy(part)
            end
            seal.state = "done"
        end
    end
end

local function update_signs(t)
    for _, rec in ipairs(G.signs) do
        if t - rec.last > 7 and dist_to(rec.lx, rec.ly) < 2400 and not in_view(rec.lx, rec.ly, SIGN_Z, 0.2) then
            rec.last = t
            rec.flip = rec.flip + 1
            local text = (rec.flip % 2 == 1) and "< EXIT" or "EXIT >"
            if rec.flip % 5 == 0 then
                text = "EXIT ?"
            end
            set_sign(rec, text)
        end
    end
end

local function update_chair(t)
    local chair = G.chair
    if chair == nil or t - (chair.last or 0) < 0.45 then
        return
    end
    chair.last = t
    local d = dist_to(chair.lx, chair.ly)
    if G.roomId == chair.room and d > 150 and not in_view(chair.lx, chair.ly, 50, 0.3) then
        local room = G.rooms[chair.room]
        local step = math.min(46, d - 140)
        local nx = chair.lx + (G.px - chair.lx) / d * step
        local ny = chair.ly + (G.py - chair.ly) / d * step
        nx = math.max(room.x * CELL + 60, math.min(room.x * CELL + CELL - 60, nx))
        ny = math.max(room.y * CELL + 60, math.min(room.y * CELL + CELL - 60, ny))
        move_chair(chair, nx, ny)
        chair.moved = (chair.moved or 0) + 1
    elseif not chair.said and (chair.moved or 0) >= 3 and d < 330 and in_view(chair.lx, chair.ly, 50, 0.8) then
        chair.said = true
        say(L("chair", "It is only a chair. It was against the wall."), 4)
    end
end

local function update_buzz()
    for _, item in ipairs(G.items) do
        if item.buzz ~= nil and G.lightK > 0 then
            item.buzz.k = (math.random() < 0.2) and 0.15 or (0.7 + math.random() * 0.5)
            apply_light(item.buzz)
        end
    end
end

-- Every so often one lamp somewhere stutters for no reason.
local function update_ambient(t)
    if t < (G.nextFlick or (G.builtAt + 8)) or G.lightK == 0 then
        return
    end
    G.nextFlick = t + 5 + math.random() * 9
    local rooms = G.level.rooms
    local room = rooms[math.random(1, #rooms)]
    local rec = room.light
    if rec == nil or rec.k < 0.5 then
        return
    end
    local pattern = { 0.15, 1, 0.3, 1, 0.1, 0.6, 1 }
    for index, k in ipairs(pattern) do
        after(index * 0.09, function()
            rec.k = k
            apply_light(rec)
        end)
    end
    if room.id == G.roomId then
        sfx("hum", 0.5)
    end
end

local function update_doors()
    for _, door in ipairs(G.doors) do
        if not door.open and G.have[door.lock] and dist_to(door.lx, door.ly) < 270 then
            door.open = true
            for _, part in ipairs(door.parts) do
                destroy(part)
            end
            sfx("unlock")
            say(L("keyTurns", "The brass key turns before you touch the lock."), 4)
        end
    end
end

local function update_fake(t)
    local fake = G.fake
    if fake.state ~= "open" or G.zone ~= "fake" or G.busy then
        return
    end
    if G.px < -FAKE_LEN + 260 then
        fake.state = "closing"
        G.busy = true
        sfx("knock")
        fade(0, 1, 0.25, { 0, 0, 0 }, true)
        after(0.9, function()
            local room = fake.room
            plug(room, "W", nil)
            destroy(fake.sign.actor)
            destroy(fake.plate)
            local cx, cy = room_center(room)
            teleport(cx, cy, 0)
            fade(1, 0, 1.4, { 0, 0, 0 }, false)
            say(L("noDoor", "There was never a door there."), 5)
            fake.state = "gone"
            G.busy = false
        end)
    end
end

local function open_white()
    local hall = G.hall
    hall.white = true
    local xe, yc = hall.xe, hall.yc
    box(xe - 6, yc - HALL_HALF, 0, xe - 2, yc + HALL_HALF, HEIGHT, WHITE, { ghost = true })
    local glow = light(xe - 260, yc, 160, 200000, 2600, { 1, 1, 1 }, "hall-end")
    hall.glow = glow
    hall_refresh()
    sfx("unlock")
    say(L("hallLight", "There is light at the end. Keep walking."), 5)
end

local function start_epilogue()
    local epi = G.epi
    if epi.state ~= "idle" then
        return
    end
    epi.state = "arrived"
    G.escaped = true
    local total = math.floor(os.clock() - G.startTime)
    teleport(epi.cx - 60, epi.cy, 0)
    fade(1, 0, 2.5, { 1, 1, 1 }, false)
    G.big = L("epiBig", "YOU FOUND THE WAY OUT")
    say(string.format("%s   LOOP %d   %d:%02d", G.level.title:upper(), G.loop, math.floor(total / 60), total % 60), 6)
    after(6.5, function()
        G.big = ""
        say(L("epi1", "An elevator. The same elevator."), 4)
    end)
    after(11, function()
        say(L("epi2", "It only has one button."), 4)
        sfx("hum", 0.8)
    end)
    after(15.5, function()
        G.big = L("epiEnd", "THE END?")
        set_sign(epi.sign, L("epiSign", "LEVEL 0"))
        sfx("unlock")
        epi.glow.k = 1
        apply_light(epi.glow)
        slide(epi.door, epi.doorX + TH / 2, epi.cy, 110, 340, 2.2, function()
            epi.state = "open"
        end)
    end)
    after(21, function()
        G.big = ""
        say(L("epi3", "The doors are open. They were always going to open."), 5)
    end)
end

local function update_hall(t)
    local hall = G.hall
    if G.zone ~= "hall" or G.busy then
        return
    end
    local x = G.px - hall.x0
    if not hall.entered and x > 120 then
        hall.entered = true
        sfx("drone", 0.7)
        say(L("hallEnter", "DO NOT LOOK BACK."), 4)
    end
    if hall.white then
        for k, rec in ipairs(hall.lights) do
            if rec.k > 0 and (k - 0.5) * SEG < x - 500 then
                rec.k = 0
                apply_light(rec)
            end
        end
        if x > SEGS * SEG - 230 and G.epi.state == "idle" then
            G.busy = true
            fade(0, 1, 1.0, { 1, 1, 1 }, true)
            after(1.3, function()
                G.busy = false
                start_epilogue()
            end)
        end
        return
    end
    if x > 420 and G.fwd.X < -0.35 and t - (hall.lastLook or 0) > 3 then
        hall.lastLook = t
        if hall.passes > 0 then
            hall.passes = 0
            hall_refresh()
            sfx("knock")
            blackout(0.35)
            say(L("hallLooked", "It noticed you checking. The hall is long again."), 4)
        else
            say(L("hallLook", "Do not look back."), 3)
        end
    end
    if x > 3 * SEG then
        local p = G.pawn:K2_GetActorLocation()
        G.pawn:K2_SetActorLocation({ X = p.X - SEG, Y = p.Y, Z = p.Z }, false, {}, true)
        hall.passes = hall.passes + 1
        if hall.passes >= PASSES then
            open_white()
        else
            hall_refresh()
            if hall.passes == 2 then
                sfx("knock", 0.8)
                say(L("hallPace", "Something keeps pace behind you."), 4)
            elseif hall.passes == 4 then
                say(L("hallSigns", "The signs are counting down. You are almost sure of it."), 4)
            end
        end
    end
end

local function update_epi()
    local epi = G.epi
    if epi.state == "open" and G.zone == "epi" and G.px > epi.doorX + 70 and not G.busy then
        G.busy = true
        fade(0, 1, 1.0, { 1, 1, 1 }, true)
        after(1.3, function()
            local origin, loop, god, host = G.O, G.loop + 1, G.god, G.host
            -- Parts carried out of this loop do not open the next one.
            local spent = {}
            if host then
                local carried = scan_carried()
                for id, def in pairs(G.partDef) do
                    spent[id] = carried[def] or 0
                end
            end
            H.teardown()
            H.build(origin, { loop = loop, god = god, host = host, spent = spent })
            teleport(room_center(G.rooms[G.level.start]))
            fade(1, 0, 2.5, { 1, 1, 1 }, false)
            say(L("loop", "LOOP {n}. The lamps hum like they remember you.", { n = loop }), 6)
        end)
    end
end

local function update_whisper(t)
    if G.zone == "room" and not G.whispered and G.roomSince ~= nil and t - G.roomSince > 40 then
        G.whispered = true
        local lines = WHISPERS
        if G.level.text ~= nil and type(G.level.text.whispers) == "table" and #G.level.text.whispers > 0 then
            lines = G.level.text.whispers
        end
        G.whisperIndex = (G.whisperIndex or 0) % #lines + 1
        say(lines[G.whisperIndex], 5)
    end
end

-- The Skin Stealer has no patrol route on this floor, so it only chases what walks into its sight.
-- During a hunt it is walked toward the nearest player until its own senses lock on. The grab is the game's.
-- Its behaviour tree cancels every walk it did not start itself. So the tree is stopped while the mod
-- walks it, and started again once it stands close enough to see the player.
local function monster_brain(on)
    if (G.brainOff == true) ~= on then
        return
    end
    pcall(function()
        local brain = G.monster:GetController().BrainComponent
        if on then
            brain:RestartLogic()
        else
            brain:StopLogic("led")
        end
        G.brainOff = not on
    end)
end

local function in_refuge(lx, ly)
    local room = G.grid[math.floor(lx / CELL) .. "_" .. math.floor(ly / CELL)]
    return room ~= nil and G.refuge[room.id] == true
end

-- True while every player on the floor stands in a refuge. Looked up twice a second.
local function everyone_hidden(t)
    if next(G.refuge) == nil then
        return false
    end
    if t - (G.hiddenAt or 0) < 0.5 then
        return G.hidden == true
    end
    G.hiddenAt = t
    local seen, hidden = 0, 0
    for _, survivor in ipairs(survivors()) do
        pcall(function()
            local at = survivor:K2_GetActorLocation()
            local lx, ly = at.X - G.O.x, at.Y - G.O.y
            if math.abs(at.Z - G.O.z) < 600 and lx < G.hall.x0 then
                seen = seen + 1
                if in_refuge(lx, ly) then
                    hidden = hidden + 1
                end
            end
        end)
    end
    G.hidden = seen > 0 and hidden == seen
    return G.hidden
end

local function lead_monster(t, mx, my)
    if t - (G.ledAt or 0) < 1.2 then
        return
    end
    G.ledAt = t
    local controller, chasing = nil, false
    pcall(function()
        controller = G.monster:GetController()
        local target = controller.Blackboard:GetValueAsObject(FName("ChaseActor"))
        chasing = target ~= nil and target:IsValid()
    end)
    if not valid(controller) then
        return
    end
    if chasing or G.monster.bIsInMontage == true then
        G.ledFrom = nil
        monster_brain(true)
        return
    end
    local goal, best = nil, math.huge
    for _, survivor in ipairs(survivors()) do
        pcall(function()
            local at = survivor:K2_GetActorLocation()
            local lx, ly = at.X - G.O.x, at.Y - G.O.y
            local d = (lx - mx) ^ 2 + (ly - my) ^ 2
            if d < best and math.abs(at.Z - G.O.z) < 600 and lx < G.hall.x0 and not in_refuge(lx, ly) then
                goal, best = at, d
            end
        end)
    end
    if goal == nil or best < LEAD_STOP * LEAD_STOP then
        -- Nobody to walk to, or close enough: its own senses and tree take it from here.
        G.ledFrom = nil
        monster_brain(true)
        return
    end
    monster_brain(false)
    -- Ordered to walk and still on the same spot: it stands against a wall where no path starts.
    -- Mid-room it finds one. If that room is a dead end too, it starts over from the room it patrols.
    local from = G.ledFrom
    if from ~= nil and math.abs(from.x - mx) < 25 and math.abs(from.y - my) < 25 then
        local cx = math.floor(mx / CELL) * CELL + CELL / 2
        local cy = math.floor(my / CELL) * CELL + CELL / 2
        local wedge = G.ledWedge
        if wedge ~= nil and math.abs(wedge.x - mx) < 60 and math.abs(wedge.y - my) < 60 then
            cx, cy = room_center(G.monsterHome)
        end
        G.ledWedge = { x = mx, y = my }
        monster_to(cx, cy)
        mx, my = cx, cy
    end
    G.ledFrom = { x = mx, y = my }
    pcall(function()
        G.ai:SimpleMoveToLocation(controller, goal)
    end)
end

local function update_monster(t)
    if t - (G.monsterTick or 0) < 0.4 then
        return
    end
    G.monsterTick = t
    if not G.host then
        -- The host's Skin Stealer and its hunts reach other players through the game itself.
        return
    end
    if not valid(G.monster) then
        if t - G.builtAt > 4 and (G.monsterTries or 0) < 3 then
            G.monsterTries = (G.monsterTries or 0) + 1
            spawn_monster()
        end
        return
    end
    local m = G.monster:K2_GetActorLocation()
    local mx, my, mz = m.X - G.O.x, m.Y - G.O.y, m.Z - G.O.z
    local home = G.monsterHome
    if mz < -500 or mx > G.hall.x0 + 200 then
        monster_to(room_center(home))
        return
    end
    local d = dist_to(mx, my)
    local room = G.rooms[G.roomId or ""]
    if room ~= nil and room.light ~= nil and G.zone == "room" and (G.exit == nil or G.exit.state == "shut" or room.id ~= G.level.exit.room) then
        local want = 1
        if d < 950 then
            want = 0.25 + math.random() * 0.9
            if not G.heard and d < 700 then
                G.heard = true
                sfx("hum", 0.9)
                say(L("monsterNear", "The lamps stutter. {name} is close.",
                    { name = (G.level.monsters[1] and G.level.monsters[1].name) or "Something" }), 4)
            end
        else
            G.heard = false
        end
        if room.light.k ~= want then
            room.light.k = want
            apply_light(room.light)
        end
        if G.lastLit ~= nil and G.lastLit ~= room and G.lastLit.light.k ~= 1 then
            G.lastLit.light.k = 1
            apply_light(G.lastLit.light)
        end
        G.lastLit = room
    end
    if not G.monsterArmed then
        G.monsterArmed = true
        arm_monster()
    end
    -- A grab that never played leaves it frozen. Let it move again.
    local frozen = false
    pcall(function()
        frozen = G.monster.bIsInMontage == true and not G.monster.Mesh:GetAnimInstance():IsAnyMontagePlaying()
    end)
    if frozen then
        G.frozenAt = G.frozenAt or t
        if t - G.frozenAt > 5 then
            G.frozenAt = nil
            pcall(function()
                G.monster.bIsInMontage = false
            end)
        end
    else
        G.frozenAt = nil
    end
    -- Hunts: the lamps die and the game's own lights-out tag sends it after you. Its grab kills.
    local dark = level_is_dark()
    local hunt = G.hunt
    if hunt == nil then
        if dark and G.zone == "room" then
            G.hunt = { native = true, t0 = t }
            set_lights(DARK_K)
            sfx("knock")
            say(L("huntStart", "The lights are out. It hunts in the dark. Keep your flashlight on it."), 5)
        elseif t > G.nextHunt and G.zone == "room" and not G.busy then
            start_hunt(16 + math.random() * 6)
        end
    elseif hunt.native then
        if not dark then
            end_hunt(false)
        end
    elseif t > hunt.untilT or G.zone ~= "room" then
        end_hunt(G.zone ~= "room")
    elseif not G.god then
        -- While everybody is in a refuge the level is not told it is dark, so nothing is sent hunting.
        local hidden = everyone_hidden(t)
        set_level_dark(not hidden)
        if hidden and not hunt.hid then
            hunt.hid = true
            say(L("refuge", "It does not come in here. Wait for the lamps."), 4)
        end
    end
    -- The dark gives you a few seconds before it starts coming.
    if G.hunt ~= nil and not G.god and t - G.hunt.t0 > LEAD_AFTER then
        lead_monster(t, mx, my)
    else
        monster_brain(true)
    end
    if G.god then
        if dark and G.hunt ~= nil and not G.hunt.native then
            set_level_dark(false)
        end
        if d < (G.hunt ~= nil and 750 or 320) then
            local far, farD = home, -1
            for _, id in ipairs(G.level.monsters[1].patrol) do
                local cx, cy = room_center(G.rooms[id])
                local away = dist_to(cx, cy)
                if away > farD then
                    far, farD = G.rooms[id], away
                end
            end
            monster_to(room_center(far))
        end
        return
    end
    -- Between hunts it stalks on its own. If it lost you, it turns up one room over, out of sight.
    if G.hunt == nil and d > 2200 and t - (G.movedMonsterAt or G.builtAt) > 45 and room ~= nil and G.zone == "room" then
        for _, n in ipairs(neighbors(room)) do
            local cx, cy = room_center(n.room)
            if not in_view(cx, cy, 150, 0.1) then
                G.movedMonsterAt = t
                monster_to(cx, cy)
                break
            end
        end
    end
end

local function update_hud(t)
    local sub = G.sub
    if sub ~= nil and t > sub.untilT then
        G.sub = nil
        sub = nil
    end
    if sub == nil and #G.subs > 0 then
        local nextSub = table.remove(G.subs, 1)
        G.sub = { text = nextSub.text, untilT = t + nextSub.dur, kind = nextSub.kind }
        sub = G.sub
    end
    if sub ~= nil and #G.subs > 2 then
        sub.untilT = math.min(sub.untilT, t + 1.5)
    end
    hud_set("sub", sub and sub.text or "")
    hud_set("big", G.big or "")
    local target = nil
    if G.zone == "room" and not G.busy then
        target = target_now()
    end
    hud_set("prompt", (G.zone == "room" and not G.busy) and prompt_for(target) or "")
    local parts, haveCount = {}, 0
    for _, id in ipairs(G.level.exit.requires) do
        if G.have[id] then
            haveCount = haveCount + 1
        end
        parts[#parts + 1] = (PART_LABEL[id] or id:upper()) .. (G.have[id] and " [X]" or " [ ]")
    end
    if G.exit ~= nil and G.exit.state ~= "shut" then
        parts = { "THE DOOR IS OPEN" }
    end
    local total = #G.level.rooms
    local shown = G.glitch and (total + 1) or G.visitedCount
    local where = "ROOM " .. string.format("%02d/%02d", shown, total)
    if G.zone == "hall" then
        where = "ROOM ??/" .. total
    elseif G.zone == "epi" then
        where = L("epiSign", "LEVEL 0")
    end
    local status = G.level.title:upper() .. (G.loop > 1 and ("   LOOP " .. G.loop) or "") .. "\n"
        .. where .. "   HUNGER " .. math.floor(G.hunger) .. "   STAMINA " .. math.floor(G.stamina) .. "\n"
        .. table.concat(parts, "  ") .. (G.have.small_key and "   KEY" or "")
        .. (G.hunt ~= nil and ("\n" .. L("hudHunt", "LIGHTS OUT")) or "")
        .. (G.god and "\nTEST: GODMODE" or "")
    hud_set("status", status)
end

local function run_timers(t)
    local due = {}
    local keep = {}
    for _, timer in ipairs(G.timers) do
        if timer.at <= t then
            due[#due + 1] = timer
        else
            keep[#keep + 1] = timer
        end
    end
    G.timers = keep
    local mine = G
    for _, timer in ipairs(due) do
        timer.fn()
        if G ~= mine then
            return false
        end
    end
    return true
end

local function run_anims(t)
    local keep = {}
    for _, anim in ipairs(G.anims) do
        local f = math.min(1, (t - anim.t0) / anim.dur)
        local z = anim.z0 + (anim.z1 - anim.z0) * (f * f * (3 - 2 * f))
        pcall(function()
            anim.actor:K2_SetActorLocation(W(anim.lx, anim.ly, z), false, {}, true)
        end)
        if f < 1 then
            keep[#keep + 1] = anim
        elseif anim.done then
            anim.done()
        end
    end
    G.anims = keep
end

local function guard(name, fn, t)
    local ok, err = pcall(fn, t)
    if not ok then
        local key = name .. ": " .. tostring(err)
        if not G.errs[key] then
            G.errs[key] = true
            log("Tick error " .. key)
        end
    end
    return ok, err
end

-- Drop every reference without destroying anything: the level that owned it is going or gone.
-- The HUD is the exception. It belongs to the game, not the level, and would stay on screen with its
-- last text. This can run off the game thread, so the HUD is only set aside here and taken down by the next tick.
local staleHud = nil

local function release()
    if HUD ~= nil then
        staleHud = HUD.widget
    end
    earlyUntil = os.clock() + EARLY_FOR
    HUD = nil
    rawset(_G, "CBR_HUD", nil)
    G = nil
end

function H.tick()
    local t = os.clock()
    if G == nil or not G.built then
        if staleHud ~= nil then
            local widget = staleHud
            staleHud = nil
            pcall(function()
                if valid(widget) then
                    widget:RemoveFromParent()
                end
            end)
        end
        early_objectives(t)
        return
    end
    if not valid(G.pc) then
        G.pc = find_controller()
        if not valid(G.pc) then
            return
        end
    end
    -- Dying restarts the level. Everything built here belongs to the old one, so let go of it
    -- before the game takes it away.
    local here, leaving = true, false
    pcall(function()
        local world = G.pc:GetWorld()
        if G.worldAt ~= nil and world:GetAddress() ~= G.worldAt then
            here = false
            return
        end
        leaving = world.GameState.MatchState:ToString() == "LeavingMap"
    end)
    if not here or leaving then
        log(leaving and "The level is restarting. Letting go of the floor." or "The level changed. Letting go of the floor.")
        release()
        return
    end
    local pawn = G.pc.Pawn
    if not valid(pawn) then
        return
    end
    G.pawn = pawn
    local p = pawn:K2_GetActorLocation()
    G.px, G.py, G.pz = p.X - G.O.x, p.Y - G.O.y, p.Z - G.O.z
    local camera = G.pc.PlayerCameraManager
    local cl, cr = camera:GetCameraLocation(), camera:GetCameraRotation()
    local yaw, pitch = math.rad(cr.Yaw), math.rad(cr.Pitch)
    G.cam = { x = cl.X - G.O.x, y = cl.Y - G.O.y, z = cl.Z - G.O.z }
    G.fwd = { X = math.cos(pitch) * math.cos(yaw), Y = math.cos(pitch) * math.sin(yaw), Z = math.sin(pitch) }
    local mine = G
    local ok, alive = guard("timers", run_timers, t)
    if G ~= mine or (ok and alive == false) then
        return
    end
    guard("anims", run_anims, t)
    guard("zone", update_zone, t)
    guard("seal", update_seal, t)
    guard("signs", update_signs, t)
    guard("chair", update_chair, t)
    guard("doors", update_doors, t)
    guard("buzz", update_buzz, t)
    guard("ambient", update_ambient, t)
    guard("fake", update_fake, t)
    guard("hall", update_hall, t)
    if G ~= mine then
        return
    end
    guard("epi", update_epi, t)
    guard("whisper", update_whisper, t)
    guard("monster", update_monster, t)
    guard("items", update_items, t)
    guard("objectives", update_objectives, t)
    guard("hints", update_hints, t)
    guard("menu", update_menu_cover, t)
    guard("hud", update_hud, t)
    if G.god and not G.godSet then
        G.godSet = true
        pcall(function()
            pawn:SetCanBeDamaged(false)
        end)
    end
end

function H.teardown()
    if G == nil then
        return
    end
    if G.hunt ~= nil and G.host and not G.hunt.native then
        set_level_dark(false)
        announce_lights(true)
    end
    for _, actor in ipairs(G.actors) do
        destroy(actor)
    end
    G.built = false
    G = nil
end

-- The level reloaded underneath us: the old actors are already gone.
function H.forget()
    release()
end

function H.build(origin, opts)
    opts = opts or {}
    local level = ctx.level()
    if level == nil then
        log("No level file. Nothing to build.")
        return false
    end
    if G ~= nil then
        H.teardown()
    end
    G = {
        O = origin, level = level, actors = {}, ours = {}, mids = {}, lights = {}, items = {}, signs = {}, doors = {},
        timers = {}, anims = {}, subs = {}, have = {}, consumed = {}, visited = {}, visitedCount = 0, errs = {},
        hunger = level.rules.hungerStart, stamina = level.rules.staminaStart, lightK = 1,
        loop = opts.loop or 1, god = opts.god == true, host = opts.host ~= false, shadows = opts.shadows ~= false,
        seal = { state = "armed" }, zone = "room", big = "", px = 0, py = 0, pz = 0,
        cam = { x = 0, y = 0, z = 0 }, fwd = { X = 1, Y = 0, Z = 0 },
        picked = {}, carried = {}, spent = opts.spent or {}, partDef = {}, partIds = {}, food = {}, foodTotal = {},
        foodLow = {}, realItems = 0,
    }
    if opts.record then
        G.record = {}
    end
    if type(level.editor) == "table" and type(level.editor.remove) == "table" then
        G.removed = {}
        for _, key in ipairs(level.editor.remove) do
            G.removed[key] = true
        end
    end
    for _, id in ipairs(level.exit.requires) do
        G.partIds[#G.partIds + 1] = id
    end
    local locks = {}
    for _, link in ipairs(level.links) do
        if link.lock ~= nil and not locks[link.lock] then
            locks[link.lock] = true
            G.partIds[#G.partIds + 1] = link.lock
        end
    end
    G.pc = find_controller()
    G.pawn = valid(G.pc) and G.pc.Pawn or survivors()[1]
    G.world = valid(G.pawn) and G.pawn:GetWorld() or FindFirstOf("World")
    pcall(function()
        G.worldAt = G.world:GetAddress()
    end)
    G.cls = {
        mesh = asset("/Script/Engine.StaticMeshActor"),
        point = asset("/Script/Engine.PointLight"),
        text = asset("/Script/Engine.TextRenderActor"),
        textblock = asset("/Script/UMG.TextBlock"),
    }
    G.mesh = {
        cube = asset("/Engine/BasicShapes/Cube.Cube"),
        cyl = asset("/Engine/BasicShapes/Cylinder.Cylinder"),
        sphere = asset("/Engine/BasicShapes/Sphere.Sphere"),
    }
    G.basic = asset("/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial")
    G.gs = asset("/Script/Engine.Default__GameplayStatics")
    G.ai = asset("/Script/AIModule.Default__AIBlueprintHelperLibrary")
    G.snd = {
        knock = asset("/Game/Audio/SFX/W_DoorKnocking2.W_DoorKnocking2"),
        hum = asset("/Game/Audio/SFX/W_LowHumFlickering.W_LowHumFlickering"),
        unlock = asset("/Game/Audio/SFX/W_DoorUnlocked.W_DoorUnlocked"),
        drone = asset("/Game/Audio/Ambience/Scary_Drone.Scary_Drone"),
    }
    if G.world == nil or G.cls.mesh == nil or G.mesh.cube == nil or G.basic == nil then
        log("Engine shapes are missing. Cannot build.")
        G = nil
        return false
    end
    G.rooms, G.grid, G.links, G.w, G.h = {}, {}, {}, 0, 0
    for _, room in ipairs(level.rooms) do
        G.rooms[room.id] = room
        G.grid[room.x .. "_" .. room.y] = room
        G.w = math.max(G.w, room.x + 1)
        G.h = math.max(G.h, room.y + 1)
    end
    for _, link in ipairs(level.links) do
        G.links[link.a .. "|" .. link.b] = link
        G.links[link.b .. "|" .. link.a] = link
    end
    -- Looks the level file brings along. A field it leaves out comes from bare concrete.
    G.themes = {}
    if type(level.themes) == "table" then
        for name, own in pairs(level.themes) do
            local th = {}
            for field, value in pairs(THEMES.concrete_hall) do
                th[field] = value
            end
            for field, value in pairs(own) do
                th[field] = value
            end
            G.themes[name] = th
        end
    end
    -- On floors that say so, a room with somewhere to rest is a refuge from the hunt.
    G.refuge = {}
    if level.rules.refuge then
        for id, contents in pairs(level.contents) do
            if contents.rest ~= nil and #contents.rest > 0 then
                G.refuge[id] = true
            end
        end
    end
    local exitRoom = G.rooms[level.exit.room]
    G.exitKey = exitRoom.x .. "_" .. exitRoom.y
    G.fakeRoom = "r0_" .. (G.h - 1)
    build_hall()
    build_epilogue()
    for _, room in ipairs(level.rooms) do
        build_room(room)
    end
    build_ceiling_grid()
    build_signs()
    local sx, sy = room_center(G.rooms[level.start])
    box(sx - 130, sy - 130, 0, sx + 130, sy + 130, 1, { 0.10, 0.08, 0.04 }, { ghost = true })
    local chairRoom = G.rooms[(level.solution.steps[9] and level.solution.steps[9].to) or "r2_1"] or G.rooms["r2_1"]
    if chairRoom ~= nil then
        local cx, cy = room_center(chairRoom)
        G.chair = make_chair(cx + 290, cy + 290)
        G.chair.room = chairRoom.id
    end
    build_editor()
    hall_refresh()
    refresh_exit_lamps()
    move_nav_bounds()
    ensure_hud()
    mood()
    G.builtAt = os.clock()
    G.nextHunt = G.builtAt + 100 + math.random() * 40
    G.startTime = G.builtAt
    G.roomId = level.start
    G.roomSince = G.builtAt
    G.visited[level.start] = true
    G.visitedCount = 1
    G.built = true
    log("Built " .. tostring(level.pickerLabel) .. " loop " .. G.loop .. " with " .. #G.actors .. " pieces")
    -- A floor written from a wiki page says where its words come from.
    if G.loop == 1 and type(level.wiki) == "table" and type(level.wiki.credit) == "string" then
        log(level.wiki.credit)
    end
    return true
end

local function stop_elevator_ride()
    for _, player in ipairs(FindAllOf("LevelSequencePlayer") or {}) do
        pcall(function()
            player:Stop()
        end)
    end
    for _, actor in ipairs(FindAllOf("BP_ElevatorFinal_C") or {}) do
        pcall(function()
            actor:SetActorTickEnabled(false)
        end)
    end
end
H.stop_elevator_ride = stop_elevator_ride

local function step_onto_floor()
    local lx, ly = room_center(G.rooms[G.level.start])
    for _, pawn in ipairs(survivors()) do
        pcall(function()
            pawn:K2_DetachFromActor(0, 0, 0)
        end)
        pcall(function()
            pawn.CharacterMovement.Velocity = { X = 0, Y = 0, Z = 0 }
        end)
        pcall(function()
            pawn:K2_SetActorLocation(W(lx, ly, 110), false, {}, true)
        end)
    end
    pcall(function()
        G.pc:SetControlRotation({ Pitch = 0, Yaw = 0, Roll = 0 })
    end)
end

local function show_player()
    for _, className in ipairs({ "CineCameraActor", "LevelSequenceActor", "BP_ElevatorFinal_C" }) do
        for _, actor in ipairs(FindAllOf(className) or {}) do
            pcall(function()
                actor:SetActorTickEnabled(false)
                actor:SetActorHiddenInGame(true)
                actor:SetActorEnableCollision(false)
            end)
        end
    end
    pcall(function()
        G.pc:SetCinematicMode(false, false, false, false, false)
    end)
    pcall(function()
        G.pc:SetViewTargetWithBlend(G.pc.Pawn, 0, 0, 0, false)
    end)
    pcall(function()
        G.pc.PlayerCameraManager:StopCameraFade()
    end)
end

-- Called while the elevator is still moving: the floor is built around the car.
function H.enter(opts)
    opts = opts or {}
    local level = ctx.level()
    local controller = find_controller()
    if level == nil or not valid(controller) then
        return false
    end
    local origin = opts.origin
    if origin == nil then
        local cam = nil
        pcall(function()
            cam = controller.PlayerCameraManager:GetCameraLocation()
        end)
        if cam == nil or cam.X == nil then
            return false
        end
        local start = nil
        for _, room in ipairs(level.rooms) do
            if room.id == level.start then
                start = room
            end
        end
        origin = { x = cam.X - (start.x * CELL + CELL / 2), y = cam.Y - (start.y * CELL + CELL / 2), z = cam.Z - 150 }
    end
    stop_elevator_ride()
    if not H.build(origin, opts) then
        return false
    end
    step_onto_floor()
    show_player()
    hide_original()
    fade(1, 0, 2.5, { 0, 0, 0 }, false)
    for step = 1, 2 do
        after(step * 0.4, function()
            stop_elevator_ride()
            step_onto_floor()
        end)
    end
    say(L("intro1", "The elevator stopped between floors."), 3.5)
    say(L("intro2", "The doors opened anyway."), 3.5)
    say(L("goal", "Find the tape, the valve and the fuse. Leave through the maintenance door."), 6)
    if G.realItems > 0 then
        say("Pick things up and eat from your inventory like anywhere else. F9 rests and tries the door.", 6)
        say(L("huntWarn", "When the lights go out it hunts, and it kills. Keep your flashlight on it."), 6)
    else
        say("F9 uses what is in front of you. Eat. Rest. Stay together.", 5)
    end
    after(7.5, function()
        G.big = G.level.title:upper()
    end)
    after(11.5, function()
        G.big = ""
    end)
    H.broadcast(true)
    return true
end

-- Co-op: the host tells other modded players where the floor is and what the group carries.
function H.broadcast(withBuild)
    if G == nil or not G.host then
        return
    end
    local list = FindAllOf("PlayerController") or {}
    if #list <= 1 then
        return
    end
    local have = {}
    for id, owned in pairs(G.have) do
        if owned then
            have[#have + 1] = id
        end
    end
    table.sort(have)
    local state = string.format("[CBR] STATE hunger=%d stamina=%d have=%s", math.floor(G.hunger), math.floor(G.stamina), table.concat(have, ","))
    local build = string.format("[CBR] BUILD %.1f %.1f %.1f", G.O.x, G.O.y, G.O.z)
    for _, controller in ipairs(list) do
        pcall(function()
            if withBuild then
                controller:ClientMessage(build)
            end
            controller:ClientMessage(state)
        end)
    end
end

function H.message(text)
    if text:find("[CBR] BUILD", 1, true) then
        local x, y, z = text:match("BUILD (%-?[%d%.]+) (%-?[%d%.]+) (%-?[%d%.]+)")
        if x ~= nil and (G == nil or not G.built) then
            H.enter({ origin = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }, host = false })
        end
    elseif text:find("[CBR] STATE", 1, true) and G ~= nil and not G.host then
        G.hunger = tonumber(text:match("hunger=(%-?%d+)")) or G.hunger
        G.stamina = tonumber(text:match("stamina=(%-?%d+)")) or G.stamina
        local have = text:match("have=([^%s]*)") or ""
        for _, id in ipairs(G.partIds) do
            G.have[id] = false
        end
        for id in string.gmatch(have, "[^,]+") do
            G.have[id] = true
        end
        refresh_exit_lamps()
    end
end

-- Test helpers, used through the dev console only.
function H.state()
    return G
end

function H.god(on)
    if G ~= nil then
        G.god = on == true
        G.godSet = false
        if G.god then
            G.hunger, G.stamina = 100, 100
        end
    end
end

function H.walk(lx, ly)
    G.ai:SimpleMoveToLocation(G.pc, W(lx, ly, 100))
end

function H.look(yaw, pitch)
    G.pc:SetControlRotation({ Pitch = pitch or 0, Yaw = yaw, Roll = 0 })
end

function H.path(ax, ay, bx, by)
    local nav = FindFirstOf("NavigationSystemV1")
    local path = nav:FindPathToLocationSynchronously(G.pawn, W(ax, ay, 100), W(bx, by, 100), nil, nil)
    if not valid(path) then
        return false, 0
    end
    return not path:IsPartial(), path:GetPathLength()
end

H.room_center = function(id)
    return room_center(G.rooms[id])
end
H.say = say
H.teleport = teleport

return H
