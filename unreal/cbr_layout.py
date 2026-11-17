"""The layout formats shared by the Unreal editor script and the tools outside the editor.

No `unreal` import here, so this part runs and is tested without the editor.

Units are Unreal units (cm). The origin is the outer corner of the first room, the floor is z = 0,
x runs along the row of rooms toward the exit hall. The mod adds its own origin when it builds.

Layout file (`unreal/layouts/<level>.layout.json`, written by scripts/dump_layout.py): everything the
mod builds by itself for a level.

    pieces  [{key, kind, at[3], size[3], rot[pitch, yaw, roll], color[r, g, b 0..1], ghost, noshadow}]
    lights  [{at[3], intensity, radius, color[r, g, b 0..1], always}]
    texts   [{at[3], yaw, text, size, color[r, g, b 0..255]}]
    rooms   [{id, theme, at[3]}]        for labels in the editor
    items   [{id, name, room, at[3]}]   for labels in the editor

Editor file (`levels/<level>.editor.json`, written by the Unreal script): what was changed by hand.

    pieces, lights, texts   as above, without key: things to add
    remove  [key]           generated pieces to take out
"""
from __future__ import annotations

import math

FORMAT = 1
KINDS = {
    "cube": "/Engine/BasicShapes/Cube",
    "cyl": "/Engine/BasicShapes/Cylinder",
    "sphere": "/Engine/BasicShapes/Sphere",
}
LIMITS = {"pieces": 4000, "lights": 200, "texts": 200, "remove": 4000}


def half_up(value: float) -> int:
    return int(math.floor(value + 0.5))


def key_of(kind: str, at, size) -> str:
    """Same key as piece_key in halls.lua."""
    return "%s|%d|%d|%d|%d|%d|%d" % (kind, half_up(at[0]), half_up(at[1]), half_up(at[2]),
                                      half_up(size[0]), half_up(size[1]), half_up(size[2]))


def kind_of_path(path: str) -> str | None:
    """'/Engine/BasicShapes/Cube.Cube' -> 'cube'. None for any other mesh."""
    base = path.split(".")[0]
    for kind, mesh in KINDS.items():
        if base == mesh:
            return kind
    return None


def _close(a, b, tolerance: float) -> bool:
    return all(abs(x - y) <= tolerance for x, y in zip(a, b))


def _angles_close(a, b, tolerance: float) -> bool:
    return all(abs((x - y + 180.0) % 360.0 - 180.0) <= tolerance for x, y in zip(a, b))


def unchanged(reference: dict, now: dict) -> bool:
    """True when a piece found in the editor is still the generated piece it came from."""
    return (
        reference["kind"] == now["kind"]
        and _close(reference["at"], now["at"], 0.5)
        and _close(reference["size"], now["size"], 0.5)
        and _angles_close(reference["rot"], now["rot"], 0.1)
        and _close(reference["color"], now["color"], 0.006)
        and bool(reference.get("ghost")) == bool(now.get("ghost"))
    )


def _piece(now: dict) -> dict:
    out = {
        "kind": now["kind"],
        "at": [round(float(v), 2) for v in now["at"]],
        "size": [round(float(v), 2) for v in now["size"]],
        "rot": [round(float(v), 2) for v in now["rot"]],
        "color": [round(float(v), 4) for v in now["color"]],
    }
    if now.get("ghost"):
        out["ghost"] = True
    if now.get("noshadow"):
        out["noshadow"] = True
    return out


def diff(layout: dict, found: dict) -> dict:
    """What the editor level adds to and takes out of the generated layout.

    found: {"pieces": [...], "lights": [...], "texts": [...]} as read from the editor. A piece that
    came from the layout carries "ref": its key. Lamps and lettering that came from the layout are
    not passed in at all: the mod runs those itself.
    """
    by_key: dict[str, list[dict]] = {}
    for piece in layout.get("pieces", []):
        by_key.setdefault(piece["key"], []).append(piece)
    kept: dict[str, int] = {}
    added: list[dict] = []
    for now in found.get("pieces", []):
        key = now.get("ref")
        originals = by_key.get(key or "", [])
        if any(unchanged(original, now) for original in originals):
            kept[key] = kept.get(key, 0) + 1
        else:
            added.append(_piece(now))
    remove = sorted(key for key in by_key if kept.get(key, 0) == 0)
    lights = []
    for lamp in found.get("lights", []):
        entry = {
            "at": [round(float(v), 2) for v in lamp["at"]],
            "intensity": round(float(lamp["intensity"]), 2),
            "radius": round(float(lamp["radius"]), 2),
            "color": [round(float(v), 4) for v in lamp["color"]],
        }
        if lamp.get("always"):
            entry["always"] = True
        lights.append(entry)
    texts = [
        {
            "at": [round(float(v), 2) for v in text["at"]],
            "yaw": round(float(text["yaw"]), 2),
            "text": str(text["text"]),
            "size": round(float(text["size"]), 2),
            "color": [int(v) for v in text["color"]],
        }
        for text in found.get("texts", [])
    ]
    return {"format": FORMAT, "level": layout.get("level"), "pieces": added, "lights": lights, "texts": texts, "remove": remove}


def problems(editor: dict, layout: dict | None = None) -> list[str]:
    """Why an editor file cannot be used. Empty when it can."""
    found: list[str] = []

    def numbers(value, count: int) -> bool:
        return (isinstance(value, list) and len(value) == count
                and all(isinstance(v, (int, float)) and math.isfinite(v) for v in value))

    for name, limit in LIMITS.items():
        entries = editor.get(name, [])
        if not isinstance(entries, list):
            found.append(f"{name} must be a list")
            editor[name] = []
        elif len(entries) > limit:
            found.append(f"{name} has {len(entries)} entries, at most {limit}")
    for index, piece in enumerate(editor.get("pieces", [])):
        where = f"pieces[{index}]"
        if not isinstance(piece, dict) or piece.get("kind") not in KINDS:
            found.append(f"{where} needs a kind out of {sorted(KINDS)}")
            continue
        if not (numbers(piece.get("at"), 3) and numbers(piece.get("size"), 3) and numbers(piece.get("rot", [0, 0, 0]), 3)):
            found.append(f"{where} needs at, size and rot as three numbers each")
        elif min(piece["size"]) <= 0:
            found.append(f"{where} has a size of zero or less")
        if not (numbers(piece.get("color"), 3) and all(0 <= v <= 4 for v in piece["color"])):
            found.append(f"{where} needs a color of three numbers")
    for index, lamp in enumerate(editor.get("lights", [])):
        where = f"lights[{index}]"
        if not (isinstance(lamp, dict) and numbers(lamp.get("at"), 3) and numbers(lamp.get("color"), 3)
                and isinstance(lamp.get("intensity"), (int, float)) and isinstance(lamp.get("radius"), (int, float))):
            found.append(f"{where} needs at, color, intensity and radius")
    for index, text in enumerate(editor.get("texts", [])):
        where = f"texts[{index}]"
        if not (isinstance(text, dict) and numbers(text.get("at"), 3) and numbers(text.get("color"), 3)
                and isinstance(text.get("text"), str) and isinstance(text.get("size"), (int, float))):
            found.append(f"{where} needs at, color, text and size")
        elif len(text["text"]) > 120:
            found.append(f"{where} is {len(text['text'])} characters, at most 120")
    for key in editor.get("remove", []):
        if not isinstance(key, str):
            found.append("remove must hold keys")
            break
    if layout is not None:
        known = {piece["key"] for piece in layout.get("pieces", [])}
        stale = [key for key in editor.get("remove", []) if isinstance(key, str) and key not in known]
        if stale:
            found.append(f"{len(stale)} removed pieces are not in the generated layout any more, e.g. {stale[0]}. "
                         "The level was made again since the editor file was exported: import and export again.")
    return found
