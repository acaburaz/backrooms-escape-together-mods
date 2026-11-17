"""Build an original Backrooms level from a generated level file.

Run:
  blender --background --python blender/build_level.py -- levels/the_yellow_static.json export/the_yellow_static.glb
"""

import json
import sys
from pathlib import Path

import bpy


def arg_after_dash() -> list[str]:
    argv = sys.argv
    if "--" not in argv:
        raise SystemExit("usage: blender --background --python blender/build_level.py -- in.json out.glb")
    return argv[argv.index("--") + 1 :]


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_material(name: str, color: tuple[float, float, float], emission: float = 0.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    principled = next(node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    principled.inputs["Base Color"].default_value = (*color, 1.0)
    principled.inputs["Roughness"].default_value = 0.86
    if emission > 0 and "Emission Color" in principled.inputs:
        principled.inputs["Emission Color"].default_value = (*color, 1.0)
        principled.inputs["Emission Strength"].default_value = emission
    return material


def add_box(name: str, location, scale, material):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    return obj


def add_figure(name: str, origin, dark):
    parts = [
        ((0, 0, 1.35), (0.28, 0.18, 0.85)),
        ((0, 0.04, 2.25), (0.16, 0.16, 0.22)),
        ((-0.28, 0.08, 1.45), (0.08, 0.08, 0.72)),
        ((0.28, 0.08, 1.45), (0.08, 0.08, 0.72)),
        ((-0.1, 0, 0.45), (0.08, 0.08, 0.45)),
        ((0.1, 0, 0.45), (0.08, 0.08, 0.45)),
    ]
    first = None
    for index, (offset, scale) in enumerate(parts):
        piece = add_box(
            f"{name}_{index}",
            (origin[0] + offset[0], origin[1] + offset[1], origin[2] + offset[2]),
            scale,
            dark,
        )
        if first is None:
            first = piece
        else:
            piece.parent = first
    first.name = name
    return first


def room_origin(room, cell):
    return (room["x"] * cell, room["y"] * cell, 0.0)


def edge_segments(span, door_center, door_width, wall_thickness):
    half = door_width / 2
    left = door_center - half
    right = door_center + half
    segments = []
    if left - span[0] > 0.2:
        segments.append((span[0], left))
    if span[1] - right > 0.2:
        segments.append((right, span[1]))
    return segments


def build(level: dict) -> int:
    cell = 8.0
    height = 3.0
    thickness = 0.16
    door_width = 1.8
    materials = {
        "yellow_wallpaper": make_material("YellowPaper", (0.78, 0.68, 0.32)),
        "damp_office": make_material("DampOffice", (0.55, 0.48, 0.32)),
        "pool_tile": make_material("PoolTile", (0.62, 0.78, 0.76)),
        "concrete_hall": make_material("Concrete", (0.45, 0.45, 0.43)),
        "drop_ceiling": make_material("DropCeiling", (0.72, 0.7, 0.6)),
        "carpet": make_material("Carpet", (0.34, 0.28, 0.16)),
        "light": make_material("Fluorescent", (0.95, 0.95, 0.82), emission=8.0),
        "dark": make_material("HallStatic", (0.02, 0.02, 0.025)),
        "food": make_material("Ration", (0.45, 0.2, 0.12)),
        "rest": make_material("Cot", (0.25, 0.22, 0.18)),
        "clue": make_material("Clue", (0.82, 0.78, 0.55)),
        "exit": make_material("ExitDoor", (0.15, 0.28, 0.16)),
        "key": make_material("BrassKey", (0.72, 0.58, 0.22)),
    }
    doors = set()
    for link in level["links"]:
        doors.add((link["a"], link["b"]))
        doors.add((link["b"], link["a"]))
    count = 0
    by_id = {room["id"]: room for room in level["rooms"]}
    for room in level["rooms"]:
        x, y, _z = room_origin(room, cell)
        wall = materials[room["theme"]]
        add_box(f"Floor_{room['id']}", (x + cell / 2, y + cell / 2, -0.08), (cell - 0.05, cell - 0.05, 0.16), materials["carpet"])
        add_box(f"Ceiling_{room['id']}", (x + cell / 2, y + cell / 2, height), (cell, cell, 0.12), materials["drop_ceiling"])
        add_box(f"Light_{room['id']}", (x + cell / 2, y + cell / 2, height - 0.16), (1.6, 0.35, 0.06), materials["light"])
        count += 3
        edges = {
            "east": ((x + cell, y), (x + cell, y + cell), "y"),
            "west": ((x, y), (x, y + cell), "y"),
            "north": ((x, y + cell), (x + cell, y + cell), "x"),
            "south": ((x, y), (x + cell, y), "x"),
        }
        openings = {name: False for name in edges}
        rx, ry = room["x"], room["y"]
        for other_id in by_id:
            ox, oy = by_id[other_id]["x"], by_id[other_id]["y"]
            if (room["id"], other_id) not in doors:
                continue
            if ox == rx + 1 and oy == ry:
                openings["east"] = True
            elif ox == rx - 1 and oy == ry:
                openings["west"] = True
            elif oy == ry + 1 and ox == rx:
                openings["north"] = True
            elif oy == ry - 1 and ox == rx:
                openings["south"] = True
        for direction, ((ax, ay), (bx, by), axis) in edges.items():
            span = (ay, by) if axis == "y" else (ax, bx)
            pieces = [(span[0], span[1])]
            if openings[direction]:
                pieces = edge_segments(span, (span[0] + span[1]) / 2, door_width, thickness)
                header_center = (span[0] + span[1]) / 2
                if axis == "y":
                    add_box(
                        f"Header_{room['id']}_{direction}",
                        (ax, header_center, 2.55),
                        (thickness, door_width, 0.9),
                        wall,
                    )
                else:
                    add_box(
                        f"Header_{room['id']}_{direction}",
                        (header_center, ay, 2.55),
                        (door_width, thickness, 0.9),
                        wall,
                    )
                count += 1
            for index, (left, right) in enumerate(pieces):
                center = (left + right) / 2
                length = right - left
                if axis == "y":
                    add_box(f"Wall_{room['id']}_{direction}_{index}", (ax, center, height / 2), (thickness, length, height), wall)
                else:
                    add_box(f"Wall_{room['id']}_{direction}_{index}", (center, ay, height / 2), (length, thickness, height), wall)
                count += 1
        contents = level["contents"][room["id"]]
        cx, cy = x + cell / 2, y + cell / 2
        for item in contents["food"]:
            add_box(f"Food_{item['id']}", (cx - 1.2, cy, 0.35), (0.22, 0.22, 0.35), materials["food"])
            count += 1
        for item in contents["rest"]:
            add_box(f"Rest_{item['id']}", (cx + 1.4, cy - 1.2, 0.18), (1.3, 0.7, 0.22), materials["rest"])
            count += 1
        for item in contents["puzzle"]:
            add_box(f"Puzzle_{item['id']}", (cx, cy + 1.3, 0.04), (0.28, 0.2, 0.02), materials["clue"])
            count += 1
        for item in contents["keys"]:
            add_box(f"Key_{item['id']}", (cx - 1.5, cy + 1.2, 0.04), (0.16, 0.05, 0.02), materials["key"])
            count += 1
        if room["id"] == level["exit"]["room"]:
            add_box("ExitDoor", (cx, cy, 1.2), (1.1, 0.12, 2.2), materials["exit"])
            count += 1
    for monster in level["monsters"]:
        home = by_id[monster["patrol"][0]]
        hx, hy, _hz = room_origin(home, cell)
        add_figure(f"Monster_{monster['id']}", (hx + cell / 2, hy + 1.5, 0), materials["dark"])
        count += 1
    return count


def export(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=str(path), export_format="GLB")


def main() -> None:
    source, dest = arg_after_dash()
    level = json.loads(Path(source).read_text(encoding="utf-8"))
    reset_scene()
    count = build(level)
    export(Path(dest))
    print(f"blender level export passed objects={count}")


if __name__ == "__main__":
    main()
