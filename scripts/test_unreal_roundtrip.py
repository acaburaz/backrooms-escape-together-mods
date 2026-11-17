"""Check the Unreal editor round trip without the editor.

    python scripts/test_unreal_roundtrip.py

1. The saved layouts in unreal/layouts are what the mod builds now.
2. unreal/cbr_unreal.py imports a layout into a stand-in editor (scripts/fake_unreal.py) and exports it
   again untouched: nothing added, nothing taken out.
3. Things are then changed the way a person would in the editor (delete, move, recolour, add shapes,
   a lamp, a text). The export holds exactly those changes.
4. generator/editor_layout.py turns the export into <level>.editor.lua, and the mod plays the level
   with it from the elevator to loop 2 (scripts/offline_check.py).

The stand-in editor follows Epic's Python API reference, not a running editor. So this proves the
round trip's logic and the mod's side of it. The calls into the real editor are still unproven.
"""
from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / "scripts"), str(ROOT / "unreal"), str(ROOT / "generator")]

import fake_unreal  # noqa: E402

sys.modules["unreal"] = fake_unreal

import cbr_layout  # noqa: E402
import cbr_unreal  # noqa: E402
import dump_layout  # noqa: E402
import editor_layout  # noqa: E402
import offline_check  # noqa: E402

LEVEL = "level_1_habitable_zone"
results: list[bool] = []


def check(name: str, good: bool, detail: str = "") -> None:
    results.append(bool(good))
    print(f"{'PASS' if good else 'FAIL'}  {name}" + (f"  ({detail})" if detail else ""))


def main() -> int:
    layout_path = ROOT / "unreal" / "layouts" / f"{LEVEL}.layout.json"
    level_lua = ROOT / "mod" / "CustomBackroomsMap" / "levels" / f"{LEVEL}.lua"

    # 1. Saved layouts are current.
    stale = []
    for level_file in sorted((ROOT / "mod" / "CustomBackroomsMap" / "levels").glob("*.lua")):
        if level_file.name.endswith(".editor.lua"):
            continue
        saved = ROOT / "unreal" / "layouts" / f"{level_file.stem}.layout.json"
        fresh = dump_layout.dump(level_file)
        if not saved.is_file() or json.loads(saved.read_text(encoding="utf-8")) != json.loads(json.dumps(fresh)):
            stale.append(level_file.stem)
    check("U1 saved layouts match what the mod builds", not stale, ", ".join(stale) or "")

    layout = json.loads(layout_path.read_text(encoding="utf-8"))
    with tempfile.TemporaryDirectory() as temp:
        temp = Path(temp)

        # 2. Import, then export untouched.
        built = cbr_unreal.import_layout(str(layout_path))
        actors = fake_unreal.get_editor_subsystem(fake_unreal.EditorActorSubsystem)
        expected = sum(len(layout[name]) for name in ("pieces", "lights", "texts", "rooms", "items"))
        check("U2 import builds every piece, lamp, sign and label", built == len(layout["pieces"]) and len(actors.actors) == expected,
              f"{len(actors.actors)} actors for {expected} entries")
        untouched = cbr_unreal.export_layout(str(layout_path), str(temp / "untouched.editor.json"))
        check("U3 an untouched level exports no changes",
              not (untouched["pieces"] or untouched["lights"] or untouched["texts"] or untouched["remove"]),
              f"{len(untouched['pieces'])} added, {len(untouched['remove'])} removed")
        check("U4 a second import into the same level is refused", cbr_unreal.import_layout(str(layout_path)) == 0)

        # 3. Change things by hand.
        generated = [actor for actor in actors.actors if "cbr.ref" in actor.get_editor_property("tags")]
        deleted, moved, recoloured = generated[40], generated[41], generated[42]
        keys = [next(tag.split(":", 1)[1] for tag in actor.get_editor_property("tags") if tag.startswith("cbr.key:"))
                for actor in (deleted, moved, recoloured)]
        actors.destroy_actor(deleted)
        moved.set_actor_location(fake_unreal.Vector(moved.location.x + 120, moved.location.y, moved.location.z))
        red = fake_unreal.MaterialInstanceConstant("/Game/CBR/Colors/MyRed")
        red.vectors["Color"] = fake_unreal.LinearColor(0.8, 0.05, 0.05)
        recoloured.static_mesh_component.set_material(0, red)

        cube = actors.spawn_actor_from_class(fake_unreal.StaticMeshActor, fake_unreal.Vector(400, 400, 50))
        cube.static_mesh_component.set_static_mesh(fake_unreal.load_asset("/Engine/BasicShapes/Cube"))
        cube.set_actor_scale3d(fake_unreal.Vector(1.0, 2.0, 1.0))
        cube.set_editor_property("tags", [fake_unreal.Name("cbr.color:0.1,0.6,0.2")])
        ghost = actors.spawn_actor_from_class(fake_unreal.StaticMeshActor, fake_unreal.Vector(600, 300, 160),
                                              fake_unreal.Rotator(pitch=90))
        ghost.static_mesh_component.set_static_mesh(fake_unreal.load_asset("/Engine/BasicShapes/Cylinder"))
        ghost.set_editor_property("tags", [fake_unreal.Name("cbr.ghost")])
        chair = actors.spawn_actor_from_class(fake_unreal.StaticMeshActor, fake_unreal.Vector(0, 0, 0))
        chair.static_mesh_component.set_static_mesh(fake_unreal.load_asset("/Game/Props/SM_Chair"))
        chair.set_actor_label("SM_Chair")
        lamp = actors.spawn_actor_from_class(fake_unreal.PointLight, fake_unreal.Vector(400, 400, 250))
        lamp.set_editor_property("tags", [fake_unreal.Name("cbr.always")])
        lamp.components[0].set_editor_property("intensity_units", fake_unreal.LightUnits.UNITLESS)
        lamp.components[0].set_intensity(6000)
        lamp.components[0].set_light_color(fake_unreal.LinearColor(1.0, 0.2, 0.2))
        note = actors.spawn_actor_from_class(fake_unreal.TextRenderActor, fake_unreal.Vector(400, 790, 200),
                                             fake_unreal.Rotator(yaw=-90))
        note.components[0].set_text("STAY TOGETHER")

        export_path = temp / f"{LEVEL}.editor.json"
        editor = cbr_unreal.export_layout(str(layout_path), str(export_path))
        colours = sorted(tuple(piece["color"]) for piece in editor["pieces"])
        check("U5 the export holds exactly the handwork",
              len(editor["pieces"]) == 4 and sorted(editor["remove"]) == sorted(keys)
              and len(editor["lights"]) == 1 and editor["lights"][0].get("always") is True
              and len(editor["texts"]) == 1 and editor["texts"][0]["text"] == "STAY TOGETHER"
              and (0.1, 0.6, 0.2) in colours and (0.8, 0.05, 0.05) in colours
              and [piece.get("ghost") for piece in editor["pieces"] if piece["kind"] == "cyl" and piece["rot"][0] == 90.0] == [True],
              f"{len(editor['pieces'])} pieces, {len(editor['remove'])} removed, {len(editor['lights'])} lamps, {len(editor['texts'])} texts")
        check("U6 a mesh the mod cannot build is left out and said so",
              any("SM_Chair" in line and line.startswith("WARNING") for line in fake_unreal.LOG))

        # 4. Into the mod's format, and through the mod.
        (temp / f"{LEVEL}.lua").write_text(level_lua.read_text(encoding="utf-8"), encoding="utf-8")
        out = editor_layout.convert(export_path, temp)
        check("U7 the export converts to the file the mod loads", out is not None and out.is_file())
        if out is not None:
            source = offline_check.with_editor(level_lua.read_text(encoding="utf-8"), out.read_text(encoding="utf-8"))
            good, _ = offline_check.play(source, f"{LEVEL}.lua + hand-made layout")
            check("U8 the mod plays the level with the hand-made layout to loop 2", good)

        # A layout that no longer fits is refused.
        stale_editor = dict(editor, remove=editor["remove"] + ["cube|1|2|3|4|5|6"])
        check("U9 handwork that refers to pieces which no longer exist is refused",
              any("not in the generated layout" in problem for problem in cbr_layout.problems(stale_editor, layout)))

    good = all(results)
    print("unreal round trip passed" if good else "unreal round trip FAILED")
    return 0 if good else 1


if __name__ == "__main__":
    sys.exit(main())
