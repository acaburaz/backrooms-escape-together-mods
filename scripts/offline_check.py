"""Run halls.lua against a stand-in for the game and play each level file through it.

    python scripts/offline_check.py                 every level file in mod/CustomBackroomsMap/levels
    python scripts/offline_check.py <level>.lua     one of them
    python scripts/offline_check.py -v              also print the mod's log lines
    CBR_HALLS=<path> python scripts/offline_check.py   check another copy of halls.lua

Needs `pip install lupa` (Lua 5.4 inside Python).

What it proves: the mod's own Lua runs from the elevator to loop 2 with this level file, with no error,
and the lines on screen are the file's. A hand-made layout beside the level (<level>.editor.lua) is
loaded with it. What it cannot prove: anything the real engine does. Mocked engine objects accept every
call, so lighting, collision, the Skin Stealer, the inventory and the objectives panel still need a run
in the game.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MOD = ROOT / "mod" / "CustomBackroomsMap"
sys.path.insert(0, str(ROOT / "generator"))
import settings  # noqa: E402


def with_editor(level_source: str, editor_source: str | None) -> str:
    """The level as main.lua hands it to halls.lua: with the hand-made layout attached."""
    if editor_source is None:
        return level_source
    return ("local level = (function()\n" + level_source + "\nend)()\nlevel.editor = (function()\n"
            + editor_source + "\nend)()\nreturn level\n")


def play(level_source: str, name: str, verbose: bool = False):
    """Play one level. Returns (good, result table from offline_scenario.lua or None)."""
    import lupa

    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    mock = lua.execute((ROOT / "scripts" / "offline_mock.lua").read_text(encoding="utf-8"))
    scenario = lua.eval("function(src, ...) return assert(load(src, 'offline_scenario.lua', 't'))(...) end")
    try:
        result = scenario(
            (ROOT / "scripts" / "offline_scenario.lua").read_text(encoding="utf-8"),
            mock,
            Path(os.environ.get("CBR_HALLS") or MOD / "Scripts" / "halls.lua").read_text(encoding="utf-8"),
            level_source,
            name,
        )
    except lupa.LuaError as error:
        print(f"  FAIL  the run stopped: {error}")
        return False, None
    good = True
    for check in result.checks.values():
        good = good and bool(check.ok)
        detail = f"  ({check.detail})" if check.detail else ""
        print(f"  {'PASS' if check.ok else 'FAIL'} {check.id}  {check.what}{detail}")
    if result.failures is not None:
        for key, trace in result.failures.items():
            if isinstance(key, str):
                print("  guarded failure:", trace.replace("\n", "\n    "))
    if verbose:
        for entry in result.logs.values():
            print("  log:", entry)
    return good, result


def run(level_file: Path, verbose: bool) -> bool:
    editor_file = level_file.with_name(level_file.stem + ".editor.lua")
    editor = editor_file.read_text(encoding="utf-8") if editor_file.is_file() else None
    good, _ = play(with_editor(level_file.read_text(encoding="utf-8"), editor), level_file.name, verbose)
    return good


def host() -> bool:
    """Start the installed main.lua the way UE4SS does and see which level it loads."""
    import lupa

    try:
        win64 = settings.win64_dir()
    except SystemExit as missing:
        print(f"  SKIP H1  {missing}")
        return True
    installed = settings.installed_mod_dir()
    main_lua = installed / "Scripts" / "main.lua"
    if not main_lua.exists():
        print("  SKIP H1  the mod is not installed in the game folder")
        return True
    active = installed / "levels" / "active.txt"
    want = active.read_text(encoding="utf-8").strip() if active.exists() else "the_yellow_static.lua"
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    lua.execute((ROOT / "scripts" / "offline_mock.lua").read_text(encoding="utf-8"))
    printed: list[str] = []
    g = lua.globals()
    lua.execute("setmetatable(_G, nil)")
    g.print = lambda *parts: printed.append(" ".join(str(part) for part in parts))
    g.CBR_WIN64 = str(win64).replace("/", chr(92))
    lua.execute(
        "function IterateGameDirectories() return { Game = { Binaries = { Win64 = { __absolute_path = CBR_WIN64 } } } } end "
        "function RegisterHook() end function RegisterKeyBind() end function NotifyOnNewObject() end"
    )
    try:
        lua.eval("function(src) return assert(load(src, 'main.lua', 't'))() end")(main_lua.read_text(encoding="utf-8"))
    except lupa.LuaError as error:
        print(f"  FAIL H1  main.lua stopped: {error}")
        return False
    loaded = [entry.strip() for entry in printed if "Loaded " in entry]
    ready = [entry.strip() for entry in printed if " ready." in entry]
    good = bool(loaded) and want in loaded[0] and bool(ready)
    print(f"  {'PASS' if good else 'FAIL'} H1  The installed main.lua loads the level named in levels/active.txt  ({want})")
    for entry in (loaded + ready) if good else printed:
        print("    " + entry.strip())
    return good


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    verbose = "-v" in sys.argv[1:]
    files = [MOD / "levels" / name for name in args] or sorted(
        path for path in (MOD / "levels").glob("*.lua") if not path.name.endswith(".editor.lua"))
    good = True
    for level_file in files:
        print(level_file.name)
        good = run(level_file, verbose) and good
    if not args:
        print("installed mod")
        good = host() and good
    print("offline check passed" if good else "offline check FAILED")
    return 0 if good else 1


if __name__ == "__main__":
    sys.exit(main())
