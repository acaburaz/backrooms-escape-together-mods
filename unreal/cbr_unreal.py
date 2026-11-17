"""Open a generated floor in the Unreal editor, change it by hand, and write the changes back for the mod.

Run inside the Unreal editor (UE 5.x) with the "Python Editor Script Plugin" switched on.
Any UE 5 project will do, also an empty one: nothing is cooked and nothing from the game is needed,
the floor is made of the engine's own basic shapes.

In the editor's Output Log, with the command type set to "Cmd":

    py "<repo>/unreal/cbr_unreal.py" import "<repo>/unreal/layouts/level_1_habitable_zone.layout.json"
    py "<repo>/unreal/cbr_unreal.py" export "<repo>/unreal/layouts/level_1_habitable_zone.layout.json"

`import` builds the floor in the level that is open (use File > New Level > Empty Level first).
`export` reads the level back and writes <repo>/levels/<level>.editor.json: what you added and what
you took out. Outside the editor, `python generator/editor_layout.py <level>` then turns that file
into the one the mod loads.

What counts on export:
  - Every Static Mesh Actor that uses the engine's Cube, Cylinder or Sphere (/Engine/BasicShapes).
    Its colour is the "Color" of its material instance (the ones under /Game/CBR/Colors; duplicate
    one and change its colour to get a new colour), or a tag  cbr.color:0.5,0.2,0.1
    Tag  cbr.ghost  = players walk through it.  Tag  cbr.noshadow  = casts no shadow.
  - Every Point Light: place, intensity, attenuation radius, colour. It goes dark with the other
    lamps during a hunt unless tagged  cbr.always
  - Every Text Render Actor: place, yaw, text, world size, colour.
  - A generated piece that you moved, resized, recoloured or deleted is taken out of the generated
    floor; if it is still there, it comes back as your own piece.
  - Not exported: anything tagged  cbr.fixed  (the generated lamps and signs: the mod runs those
    itself),  cbr.info  (room and item labels) or  cbr.ignore.  Other meshes are skipped with a note,
    because the mod can only build the three basic shapes.

This file has been exercised against a stand-in for the `unreal` module (scripts/test_unreal_roundtrip.py),
not yet inside a real editor. If a call fails in your engine version, the message in the Output Log
names it.
"""
import json
import os
import sys

import unreal

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import cbr_layout  # noqa: E402

REPO = os.path.dirname(HERE)
FOLDER_GENERATED = "CBR/Generated"
FOLDER_CEILING = "CBR/Generated/Ceiling"
FOLDER_FIXED = "CBR/Generated/Lamps and signs"
FOLDER_INFO = "CBR/Info"
COLOR_DIR = "/Game/CBR/Colors"
PARENT_MATERIAL = "/Engine/BasicShapes/BasicShapeMaterial"
CEILING_FROM = 300.0
DEFAULT_COLOR = [0.5, 0.5, 0.5]


def _log(text):
    unreal.log("[CBR] " + text)


def _warn(text):
    unreal.log_warning("[CBR] " + text)


def _actor_subsystem():
    return unreal.get_editor_subsystem(unreal.EditorActorSubsystem)


def _spawn(actor_class, at, rot=(0.0, 0.0, 0.0)):
    return _actor_subsystem().spawn_actor_from_class(
        actor_class,
        unreal.Vector(float(at[0]), float(at[1]), float(at[2])),
        unreal.Rotator(pitch=float(rot[0]), yaw=float(rot[1]), roll=float(rot[2])),
    )


def _tags(actor):
    return [str(tag) for tag in actor.get_editor_property("tags")]


def _set_tags(actor, tags):
    actor.set_editor_property("tags", [unreal.Name(tag) for tag in tags])


def _component(actor, component_class):
    return actor.get_component_by_class(component_class)


def _color_material(color, cache):
    """A material instance of the engine's basic shape material in this colour, made once per colour."""
    rgb = tuple(int(max(0.0, min(1.0, float(c))) * 255 + 0.5) for c in color)
    name = "C_%02x%02x%02x" % rgb
    if name in cache:
        return cache[name]
    path = COLOR_DIR + "/" + name
    if unreal.EditorAssetLibrary.does_asset_exist(path):
        material = unreal.EditorAssetLibrary.load_asset(path)
    else:
        material = unreal.AssetToolsHelpers.get_asset_tools().create_asset(
            name, COLOR_DIR, unreal.MaterialInstanceConstant, unreal.MaterialInstanceConstantFactoryNew())
        unreal.MaterialEditingLibrary.set_material_instance_parent(material, unreal.load_asset(PARENT_MATERIAL))
        unreal.MaterialEditingLibrary.set_material_instance_vector_parameter_value(
            material, "Color", unreal.LinearColor(rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0, 1.0))
    cache[name] = material
    return material


def _label(text, at, size, color, folder, tags, yaw=0.0):
    actor = _spawn(unreal.TextRenderActor, at, (0.0, yaw, 0.0))
    component = _component(actor, unreal.TextRenderComponent)
    component.set_text(str(text))
    component.set_world_size(float(size))
    component.set_text_render_color(unreal.Color(r=int(color[0]), g=int(color[1]), b=int(color[2]), a=255))
    try:
        component.set_horizontal_alignment(unreal.HorizTextAligment.EHTA_CENTER)
    except Exception as error:  # the enum's name differs between engine versions
        _warn("text alignment not set: %s" % error)
    actor.set_folder_path(folder)
    _set_tags(actor, tags)
    return actor


def import_layout(layout_path):
    """Build the generated floor in the open level."""
    with open(layout_path, encoding="utf-8") as handle:
        layout = json.load(handle)
    already = [actor for actor in _actor_subsystem().get_all_level_actors() if "cbr.ref" in _tags(actor)]
    if already:
        _warn("This level already holds %d generated pieces. Import into an empty level, or delete the CBR folder first."
              % len(already))
        return 0
    meshes = {kind: unreal.load_asset(path) for kind, path in cbr_layout.KINDS.items()}
    cache = {}
    pieces = layout.get("pieces", [])
    with unreal.ScopedSlowTask(len(pieces), "Building " + str(layout.get("level"))) as task:
        task.make_dialog(True)
        for index, piece in enumerate(pieces):
            if task.should_cancel():
                break
            task.enter_progress_frame(1)
            actor = _spawn(unreal.StaticMeshActor, piece["at"], piece["rot"])
            component = actor.static_mesh_component
            component.set_static_mesh(meshes[piece["kind"]])
            component.set_material(0, _color_material(piece["color"], cache))
            actor.set_actor_scale3d(unreal.Vector(*[float(v) / 100.0 for v in piece["size"]]))
            ceiling = piece["at"][2] >= CEILING_FROM
            actor.set_folder_path(FOLDER_CEILING if ceiling else FOLDER_GENERATED)
            actor.set_actor_label("gen_%04d_%s" % (index, piece["kind"]))
            tags = ["cbr.ref", "cbr.key:" + piece["key"]]
            if piece.get("ghost"):
                tags.append("cbr.ghost")
            if piece.get("noshadow"):
                tags.append("cbr.noshadow")
                component.set_editor_property("cast_shadow", False)
            _set_tags(actor, tags)
    for index, lamp in enumerate(layout.get("lights", [])):
        actor = _spawn(unreal.PointLight, lamp["at"])
        component = _component(actor, unreal.PointLightComponent)
        try:
            component.set_editor_property("intensity_units", unreal.LightUnits.UNITLESS)
        except Exception as error:
            _warn("light units not set: %s" % error)
        component.set_intensity(float(lamp["intensity"]))
        component.set_attenuation_radius(float(lamp["radius"]))
        component.set_light_color(unreal.LinearColor(lamp["color"][0], lamp["color"][1], lamp["color"][2], 1.0), True)
        actor.set_folder_path(FOLDER_FIXED)
        actor.set_actor_label("gen_lamp_%03d" % index)
        _set_tags(actor, ["cbr.fixed"])
    for index, text in enumerate(layout.get("texts", [])):
        actor = _label(text["text"], text["at"], text["size"], text["color"], FOLDER_FIXED, ["cbr.fixed"], text.get("yaw", 0.0))
        actor.set_actor_label("gen_sign_%03d" % index)
    for room in layout.get("rooms", []):
        at = [room["at"][0], room["at"][1], 200.0]
        actor = _label("%s\n%s" % (room["id"], room.get("theme", "")), at, 40, (255, 255, 0), FOLDER_INFO, ["cbr.info"])
        actor.set_actor_label("room_" + room["id"])
    for item in layout.get("items", []):
        at = [item["at"][0], item["at"][1], 130.0]
        actor = _label(item.get("name") or item["id"], at, 18, (0, 255, 255), FOLDER_INFO, ["cbr.info"])
        actor.set_actor_label("item_" + item["id"])
    _log("Built %s: %d pieces, %d lamps, %d signs. Hide the Outliner folder %s to look in from above."
         % (layout.get("level"), len(pieces), len(layout.get("lights", [])), len(layout.get("texts", [])), FOLDER_CEILING))
    return len(pieces)


def _piece_color(component, tags):
    for tag in tags:
        if tag.startswith("cbr.color:"):
            try:
                values = [float(v) for v in tag.split(":", 1)[1].split(",")]
                if len(values) == 3:
                    return values
            except ValueError:
                pass
            _warn("tag %s is not three numbers" % tag)
    material = component.get_material(0)
    if isinstance(material, unreal.MaterialInstanceConstant):
        try:
            color = unreal.MaterialEditingLibrary.get_material_instance_vector_parameter_value(material, "Color")
            return [color.r, color.g, color.b]
        except Exception as error:
            _warn("no Color on %s: %s" % (material.get_name(), error))
    return list(DEFAULT_COLOR)


def read_level():
    """What stands in the open level, as plain data for cbr_layout.diff."""
    found = {"pieces": [], "lights": [], "texts": []}
    skipped = []
    for actor in _actor_subsystem().get_all_level_actors():
        tags = _tags(actor)
        if "cbr.fixed" in tags or "cbr.info" in tags or "cbr.ignore" in tags:
            continue
        at = actor.get_actor_location()
        at = [at.x, at.y, at.z]
        rot = actor.get_actor_rotation()
        if isinstance(actor, unreal.StaticMeshActor):
            component = actor.static_mesh_component
            mesh = component.get_editor_property("static_mesh")
            kind = cbr_layout.kind_of_path(mesh.get_path_name()) if mesh is not None else None
            if kind is None:
                skipped.append(actor.get_actor_label())
                continue
            scale = actor.get_actor_scale3d()
            entry = {
                "kind": kind, "at": at, "rot": [rot.pitch, rot.yaw, rot.roll],
                "size": [scale.x * 100.0, scale.y * 100.0, scale.z * 100.0],
                "color": _piece_color(component, tags),
                "ghost": "cbr.ghost" in tags, "noshadow": "cbr.noshadow" in tags,
            }
            for tag in tags:
                if tag.startswith("cbr.key:"):
                    entry["ref"] = tag.split(":", 1)[1]
            found["pieces"].append(entry)
        elif isinstance(actor, unreal.PointLight):
            component = _component(actor, unreal.PointLightComponent)
            color = component.get_editor_property("light_color")
            try:
                if component.get_editor_property("intensity_units") != unreal.LightUnits.UNITLESS:
                    _warn("%s does not use unitless intensity; its brightness in the game will differ. "
                          "Duplicate a generated lamp instead of placing a new light." % actor.get_actor_label())
            except Exception:
                pass
            found["lights"].append({
                "at": at, "intensity": component.get_editor_property("intensity"),
                "radius": component.get_editor_property("attenuation_radius"),
                "color": [color.r / 255.0, color.g / 255.0, color.b / 255.0],
                "always": "cbr.always" in tags,
            })
        elif isinstance(actor, unreal.TextRenderActor):
            component = _component(actor, unreal.TextRenderComponent)
            color = component.get_editor_property("text_render_color")
            found["texts"].append({
                "at": at, "yaw": rot.yaw, "text": str(component.get_editor_property("text")),
                "size": component.get_editor_property("world_size"), "color": [color.r, color.g, color.b],
            })
    if skipped:
        _warn("%d static meshes are not basic shapes and were left out: %s" % (len(skipped), ", ".join(skipped[:8])))
    return found


def export_layout(layout_path, out_path=None):
    """Write what was changed by hand to levels/<level>.editor.json."""
    with open(layout_path, encoding="utf-8") as handle:
        layout = json.load(handle)
    editor = cbr_layout.diff(layout, read_level())
    wrong = cbr_layout.problems(editor, layout)
    for problem in wrong:
        _warn(problem)
    out_path = out_path or os.path.join(REPO, "levels", "%s.editor.json" % layout.get("level"))
    with open(out_path, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(editor, handle, ensure_ascii=False, indent=1)
        handle.write("\n")
    _log("Wrote %s: %d pieces, %d lamps, %d texts added, %d generated pieces taken out%s"
         % (out_path, len(editor["pieces"]), len(editor["lights"]), len(editor["texts"]), len(editor["remove"]),
            "" if not wrong else " (with %d problems, see above)" % len(wrong)))
    return editor


def main(argv):
    if len(argv) >= 3 and argv[1] == "import":
        import_layout(argv[2])
    elif len(argv) >= 3 and argv[1] == "export":
        export_layout(argv[2], argv[3] if len(argv) >= 4 else None)
    else:
        _warn('usage: py "cbr_unreal.py" import|export "<layout.json>" ["<out editor.json>"]')


if __name__ == "__main__":
    main(sys.argv)
