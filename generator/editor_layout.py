"""Turn a hand-made layout from the Unreal editor into the file the mod loads.

    python generator/editor_layout.py level_1_habitable_zone
    python generator/editor_layout.py levels/level_1_habitable_zone.editor.json

Reads levels/<level>.editor.json (written by unreal/cbr_unreal.py `export`), checks it, and writes
mod/CustomBackroomsMap/levels/<level>.editor.lua. main.lua loads that file beside <level>.lua, so
making the level again with the generator does not touch the handwork. Delete both editor files to
go back to the generated floor.

If the level was made again with another layout seed, pieces that were taken out by hand may no longer
exist. That is reported here: import the new layout into the editor and export again.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "unreal"))
import cbr_layout  # noqa: E402


def lua(value) -> str:
    """One compact Lua literal."""
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return repr(round(value, 4))
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return "{ " + ", ".join(lua(item) for item in value) + " }" if value else "{}"
    if isinstance(value, dict):
        return "{ " + ", ".join(f"{key} = {lua(item)}" for key, item in value.items()) + " }" if value else "{}"
    raise TypeError(type(value))


def to_lua(editor: dict) -> str:
    lines = ["-- Hand-made layout from the Unreal editor. Written by generator/editor_layout.py; edit in the editor, not here.",
             "return {", f"  format = {cbr_layout.FORMAT},", f"  level = {lua(editor.get('level'))},"]
    for name in ("pieces", "lights", "texts", "remove"):
        lines.append(f"  {name} = {{")
        lines += [f"    {lua(entry)}," for entry in editor.get(name, [])]
        lines.append("  },")
    lines.append("}")
    return "\n".join(lines) + "\n"


def convert(source: Path, out_dir: Path | None = None) -> Path | None:
    editor = json.loads(source.read_text(encoding="utf-8"))
    level = editor.get("level") or source.name.removesuffix(".editor.json")
    editor["level"] = level
    layout_path = ROOT / "unreal" / "layouts" / f"{level}.layout.json"
    layout = json.loads(layout_path.read_text(encoding="utf-8")) if layout_path.is_file() else None
    wrong = cbr_layout.problems(editor, layout)
    if wrong:
        for problem in wrong:
            print("  " + problem)
        print(f"{source.name} was not converted")
        return None
    out_dir = out_dir or ROOT / "mod" / "CustomBackroomsMap" / "levels"
    if not (out_dir / f"{level}.lua").is_file():
        print(f"  note: there is no {level}.lua in {out_dir}; the mod only loads this beside its level")
    out = out_dir / f"{level}.editor.lua"
    out.write_text(to_lua(editor), encoding="utf-8", newline="\n")
    print(f"wrote {out}: {len(editor['pieces'])} pieces, {len(editor['lights'])} lamps, {len(editor['texts'])} texts added, "
          f"{len(editor['remove'])} generated pieces taken out")
    return out


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    source = Path(sys.argv[1])
    if not source.is_file():
        source = ROOT / "levels" / f"{sys.argv[1]}.editor.json"
    if not source.is_file():
        print(f"{source} does not exist. Export from the Unreal editor first (unreal/cbr_unreal.py).")
        return 1
    return 0 if convert(source) is not None else 1


if __name__ == "__main__":
    sys.exit(main())
