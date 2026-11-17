"""Write down everything the mod builds for a level, so it can be opened in the Unreal editor.

    python scripts/dump_layout.py                    every level in mod/CustomBackroomsMap/levels
    python scripts/dump_layout.py <level>.lua        one of them
    python scripts/dump_layout.py --check            fail if a saved layout differs from what the mod builds now

Writes unreal/layouts/<level>.layout.json (format in unreal/cbr_layout.py). halls.lua is run against
the stand-in engine from offline_mock.lua and asked to keep a record of every shape, lamp and sign it
makes; nothing is measured by hand. A hand-made layout (<level>.editor.lua) is left out on purpose:
the layout file is what the generator made, the editor file is what was changed.

Needs `pip install lupa`.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "mod" / "CustomBackroomsMap"
OUT = ROOT / "unreal" / "layouts"
sys.path.insert(0, str(ROOT / "unreal"))
import cbr_layout  # noqa: E402

DUMP = """
local M, hallsSrc, levelSrc, levelName = ...
local level = assert(load(levelSrc, levelName, "t"))()
level.editor = nil
local H = assert(load(hallsSrc, "halls.lua", "t"))({ log = function() end, level = function() return level end })
assert(H.build({ x = 0, y = 0, z = 0 }, { record = true }) == true, "the floor did not build")
local g = H.state()
local out = { record = g.record, rooms = {}, items = {}, title = level.title }
for _, room in ipairs(level.rooms) do
    local cx, cy = H.room_center(room.id)
    out.rooms[#out.rooms + 1] = { id = room.id, theme = room.theme, at = { cx, cy, 0 } }
end
for _, item in ipairs(g.items) do
    out.items[#out.items + 1] = { id = item.id, name = item.name, room = item.room, at = { item.lx, item.ly, 0 } }
end
return out
"""


def plain(value):
    """A Lua table as lists and dicts."""
    import lupa

    if lupa.lua_type(value) != "table":
        if isinstance(value, float) and value.is_integer() and abs(value) < 1e15:
            return int(value)
        return value
    keys = list(value.keys())
    if keys and all(isinstance(key, int) for key in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        return [plain(value[index]) for index in range(1, len(keys) + 1)]
    return {str(key): plain(value[key]) for key in keys}


ORDER = ("key", "id", "name", "room", "theme", "kind", "text", "at", "size", "rot", "yaw", "color",
         "intensity", "radius", "ghost", "noshadow", "always")


def ordered(entry: dict) -> dict:
    """Lua hands fields over in no fixed order. The file should not change from run to run."""
    return {field: entry[field] for field in ORDER if field in entry} | {
        field: entry[field] for field in sorted(entry) if field not in ORDER}


def dump(level_file: Path) -> dict:
    import lupa

    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    mock = lua.execute((ROOT / "scripts" / "offline_mock.lua").read_text(encoding="utf-8"))
    run = lua.eval("function(src, ...) return assert(load(src, 'dump', 't'))(...) end")
    result = plain(run(DUMP, mock, (MOD / "Scripts" / "halls.lua").read_text(encoding="utf-8"),
                       level_file.read_text(encoding="utf-8"), level_file.name))
    layout = {
        "format": cbr_layout.FORMAT,
        "level": level_file.stem,
        "title": result.get("title"),
        "units": "cm; origin at the outer corner of the first room; floor at z = 0",
        "pieces": [], "lights": [], "texts": [],
        "rooms": result.get("rooms") or [],
        "items": result.get("items") or [],
    }
    for entry in result.get("record") or []:
        kind = entry.pop("type")
        for field in ("at", "size", "rot", "color"):
            if isinstance(entry.get(field), list):
                entry[field] = [round(float(v), 4) for v in entry[field]]
        if kind == "text":
            entry["color"] = [int(v) for v in entry["color"]]
        if kind == "piece":
            assert entry["key"] == cbr_layout.key_of(entry["kind"], entry["at"], entry["size"]), entry
        layout[{"piece": "pieces", "light": "lights", "text": "texts"}[kind]].append(ordered(entry))
    layout["rooms"] = [ordered(room) for room in layout["rooms"]]
    layout["items"] = [ordered(item) for item in layout["items"]]
    return layout


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    check = "--check" in sys.argv[1:]
    files = [MOD / "levels" / name for name in args] or sorted(
        path for path in (MOD / "levels").glob("*.lua") if not path.name.endswith(".editor.lua"))
    good = True
    OUT.mkdir(parents=True, exist_ok=True)
    for level_file in files:
        layout = dump(level_file)
        text = json.dumps(layout, ensure_ascii=False, separators=(",", ":")).replace('},{', '},\n{') + "\n"
        path = OUT / f"{level_file.stem}.layout.json"
        counts = f"{len(layout['pieces'])} pieces, {len(layout['lights'])} lamps, {len(layout['texts'])} signs"
        if check:
            same = path.is_file() and path.read_text(encoding="utf-8") == text
            good = good and same
            print(f"{'same' if same else 'DIFFERENT'}  {path.relative_to(ROOT)}  ({counts})")
        else:
            path.write_text(text, encoding="utf-8", newline="\n")
            print(f"wrote {path.relative_to(ROOT)}  ({counts})")
    if check:
        print("layouts are up to date" if good else "layouts are out of date: run python scripts/dump_layout.py")
    return 0 if good else 1


if __name__ == "__main__":
    sys.exit(main())
