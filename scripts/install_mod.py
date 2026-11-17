"""Check the mod's Lua and copy the mod into the game's UE4SS mod folder.

    python scripts/install_mod.py            check, then copy
    python scripts/install_mod.py --check    check only
    python scripts/install_mod.py --to DIR   copy to another folder (e.g. to hand the mod to a friend)

What is copied: enabled.txt, Scripts/*.lua, levels/*.lua (levels and their hand-made .editor.lua
layouts) and levels/active.txt. levels/active.txt names the level the mod loads; without it the mod
loads the_yellow_static.lua. Nothing under dev/ in the installed folder is touched.

The game folder is found through Steam (see scripts/gamedir.py). The Lua is compiled with Lua 5.4
(`pip install lupa`), the version UE4SS runs.
"""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "mod" / "CustomBackroomsMap"
sys.path.insert(0, str(ROOT / "generator"))
import settings  # noqa: E402


def files() -> list[Path]:
    found = [SOURCE / "enabled.txt"]
    found += sorted((SOURCE / "Scripts").glob("*.lua"))
    found += sorted((SOURCE / "levels").glob("*.lua"))
    if (SOURCE / "levels" / "active.txt").is_file():
        found.append(SOURCE / "levels" / "active.txt")
    return found


def check() -> bool:
    try:
        import lupa
    except ImportError:
        print("lupa is not installed, so the Lua cannot be checked. Run: pip install lupa")
        return False
    lua = lupa.LuaRuntime()
    compile_only = lua.eval("function(source, name) local chunk, err = load(source, name, 't') return err end")
    good = True
    for path in files():
        if path.suffix != ".lua":
            continue
        error = compile_only(path.read_text(encoding="utf-8"), path.name)
        print(f"  {'ok   ' if error is None else 'ERROR'} {path.relative_to(SOURCE).as_posix()}" + (f": {error}" if error else ""))
        good = good and error is None
    levels = {path.name for path in (SOURCE / "levels").glob("*.lua")}
    active = SOURCE / "levels" / "active.txt"
    if active.is_file():
        name = active.read_text(encoding="utf-8").strip()
        if name not in levels:
            print(f"  ERROR levels/active.txt names {name}, which is not in levels/")
            good = False
        else:
            print(f"  active level: {name}")
    else:
        print("  active level: the_yellow_static.lua (no levels/active.txt)")
    for path in (SOURCE / "levels").glob("*.editor.lua"):
        if path.name.replace(".editor.lua", ".lua") not in levels:
            print(f"  ERROR {path.name} has no level beside it")
            good = False
    return good


def install(target: Path) -> None:
    for path in files():
        destination = target / path.relative_to(SOURCE)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, destination)
    # What is gone here should not linger there: an old active.txt or hand-made layout would still be loaded.
    if not (SOURCE / "levels" / "active.txt").is_file():
        (target / "levels" / "active.txt").unlink(missing_ok=True)
    for stale in (target / "levels").glob("*.editor.lua"):
        if not (SOURCE / "levels" / stale.name).is_file():
            stale.unlink()
    print(f"installed to {target}")


def main() -> int:
    if not check():
        print("not installed")
        return 1
    if "--check" in sys.argv:
        return 0
    if "--to" in sys.argv:
        target = Path(sys.argv[sys.argv.index("--to") + 1]) / settings.MOD_NAME
    else:
        target = settings.installed_mod_dir()
        if not (settings.win64_dir() / "ue4ss").is_dir():
            print(f"There is no ue4ss folder in {settings.win64_dir()}. Install the UE4SS build for this game first (see README).")
            return 1
    install(target)
    return 0


if __name__ == "__main__":
    sys.exit(main())
