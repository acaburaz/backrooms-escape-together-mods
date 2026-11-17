#!/usr/bin/env python3
"""Build a solvable co-op Backrooms level and optional OpenAI flavor text.

The maze, locks, hunger, stamina, and exit puzzle are decided here.
OpenAI is only allowed to rename rooms and objects. The key is read from
the OPENAI_API_KEY environment variable and is never stored.
"""

from __future__ import annotations

import argparse
import json
import os
import random
import urllib.error
import urllib.request
from collections import deque
from pathlib import Path

import settings

ROOT = Path(__file__).resolve().parents[1]
settings.load_env()
WIDTH = 4
HEIGHT = 4
START = "r0_0"
EXIT = "r3_3"
PUZZLE_IDS = ("vhs", "valve", "fuse")
FOOD_SPECS = (
    ("almond_water", "Almond water", 40),
    ("canned_soup", "Canned soup", 40),
    ("granola", "Granola square", 40),
)
REST_SPECS = (
    ("quiet_cot", "Quiet cot", 50, False),
    ("buzzing_mattress", "Buzzing mattress", 50, True),
)
THEMES = (
    "yellow_wallpaper",
    "damp_office",
    "pool_tile",
    "concrete_hall",
    "drop_ceiling",
)
THEME_LINES = {
    "yellow_wallpaper": "Yellow paper sags off the wall. The hum in the lamps has nowhere to go.",
    "damp_office": "A damp cubicle row. The chairs are warm, as if someone stood up a moment ago.",
    "pool_tile": "White tile and standing water. The far splash never shows a swimmer.",
    "concrete_hall": "Bare concrete and a red exit sign that points back into the rooms.",
    "drop_ceiling": "A drop ceiling with one dark panel. Dust falls when the group walks in step.",
}


def room_id(x: int, y: int) -> str:
    return f"r{x}_{y}"


def parse_room(room: str) -> tuple[int, int]:
    x_text, y_text = room[1:].split("_")
    return int(x_text), int(y_text)


def neighbors(x: int, y: int) -> list[tuple[int, int]]:
    found = []
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        nx, ny = x + dx, y + dy
        if 0 <= nx < WIDTH and 0 <= ny < HEIGHT:
            found.append((nx, ny))
    return found


def link_key(a: str, b: str) -> tuple[str, str]:
    return (a, b) if a < b else (b, a)


def build_topology(rng: random.Random) -> dict:
    rooms = []
    for y in range(HEIGHT):
        for x in range(WIDTH):
            theme = THEMES[(x + y) % len(THEMES)]
            rooms.append(
                {
                    "id": room_id(x, y),
                    "x": x,
                    "y": y,
                    "theme": theme,
                    "description": THEME_LINES[theme],
                }
            )
    links = []
    seen = set()
    for y in range(HEIGHT):
        for x in range(WIDTH):
            here = room_id(x, y)
            for nx, ny in neighbors(x, y):
                other = room_id(nx, ny)
                key = link_key(here, other)
                if key in seen:
                    continue
                seen.add(key)
                links.append({"a": key[0], "b": key[1], "lock": None})

    locked = []
    exit_x, exit_y = parse_room(EXIT)
    for nx, ny in neighbors(exit_x, exit_y):
        other = room_id(nx, ny)
        locked.append(link_key(EXIT, other))
    for link in links:
        if (link["a"], link["b"]) in locked:
            link["lock"] = "small_key"

    pool = [room["id"] for room in rooms if room["id"] not in (START, EXIT)]
    rng.shuffle(pool)
    key_room = pool[0]
    puzzle_rooms = pool[1:4]
    food_rooms = pool[4:7]
    rest_rooms = [pool[7], pool[8]]

    contents: dict[str, dict] = {room["id"]: {"keys": [], "puzzle": [], "food": [], "rest": []} for room in rooms}
    contents[key_room]["keys"].append({"id": "small_key", "name": "Small brass key"})
    puzzle_names = {
        "vhs": ("Unlabeled tape", "The sleeve says the door drinks light."),
        "valve": ("Green valve", "A tag reads: third hiss, then the latch."),
        "fuse": ("Glass fuse", "Someone wrote 'east of the water' and stopped."),
    }
    for puzzle_id, where in zip(PUZZLE_IDS, puzzle_rooms):
        name, clue = puzzle_names[puzzle_id]
        contents[where]["puzzle"].append({"id": puzzle_id, "name": name, "clue": clue})
    for (food_id, name, hunger), where in zip(FOOD_SPECS, food_rooms):
        contents[where]["food"].append({"id": food_id, "name": name, "hunger": hunger})
    for (rest_id, name, stamina, calls), where in zip(REST_SPECS, rest_rooms):
        contents[where]["rest"].append(
            {"id": rest_id, "name": name, "stamina": stamina, "callsMonster": calls}
        )

    patrol = choose_patrol(rng)
    annotate_items({"rooms": rooms, "contents": contents})
    level = {
        "id": "the_yellow_static",
        "title": "The Yellow Static",
        "pickerLabel": "AI: The Yellow Static",
        "briefing": (
            "An office complex that should not fit behind the stairwell. "
            "The carpet is damp, the lamps hum, and every hall looks borrowed from the last one. "
            "Stay together. Hunger and stamina are shared. "
            "Find the tape, the valve, and the fuse, then leave through the maintenance door. "
            "Eat when the group weakens. Rest only when the side hall is empty."
        ),
        "flavorSource": "local",
        "cellSize": 800,
        "origin": {"x": 120000, "y": 120000, "z": 400},
        "rules": {
            "hungerStart": 100,
            "staminaStart": 100,
            "moveHunger": 15,
            "moveStamina": 15,
        },
        "coop": {
            "sharedVitals": True,
            "minPlayers": 1,
            "maxPlayers": 6,
            "rules": "Anyone can carry a part. The exit opens only when the group has the tape, the valve, and the fuse.",
        },
        "start": START,
        "exit": {"room": EXIT, "requires": list(PUZZLE_IDS)},
        "rooms": rooms,
        "links": links,
        "contents": contents,
        "monsters": [
            {
                "id": "hall_static",
                "name": "The Hall Static",
                "patrol": patrol,
                "damage": 20,
                "visualClass": "/Game/Entities/Smiler/BP_SmilerCharacter.BP_SmilerCharacter_C",
            }
        ],
        "solution": {"steps": []},
    }
    return level


def choose_patrol(rng: random.Random) -> list[str]:
    candidates = [room_id(x, y) for y in range(HEIGHT) for x in range(WIDTH) if room_id(x, y) != START]
    rng.shuffle(candidates)
    for origin in candidates:
        path = [origin]
        x, y = parse_room(origin)
        for _ in range(2):
            options = [room_id(nx, ny) for nx, ny in neighbors(x, y) if room_id(nx, ny) not in path]
            if not options:
                break
            nxt = rng.choice(options)
            path.append(nxt)
            x, y = parse_room(nxt)
        if len(path) == 3:
            return path
    return ["r0_2", "r0_3", "r1_3"]


def adjacency(level: dict) -> dict[str, list[tuple[str, str | None]]]:
    graph = {room["id"]: [] for room in level["rooms"]}
    for link in level["links"]:
        graph[link["a"]].append((link["b"], link["lock"]))
        graph[link["b"]].append((link["a"], link["lock"]))
    return graph


def bit_index(ids: list[str]) -> dict[str, int]:
    return {item_id: index for index, item_id in enumerate(ids)}


def collect_indexes(level: dict) -> tuple[dict[str, int], dict[str, int], dict[str, int], dict[str, int]]:
    keys, notes, foods, rests = [], [], [], []
    for room_contents in level["contents"].values():
        keys.extend(item["id"] for item in room_contents["keys"])
        notes.extend(item["id"] for item in room_contents["puzzle"])
        foods.extend(item["id"] for item in room_contents["food"])
        rests.extend(item["id"] for item in room_contents["rest"])
    return bit_index(sorted(keys)), bit_index(sorted(notes)), bit_index(sorted(foods)), bit_index(sorted(rests))


def items_in(level: dict, room: str, kind: str) -> list[dict]:
    return level["contents"][room][kind]


def apply_enter(level: dict, room: str, keys: int, notes: int, key_index, note_index) -> tuple[int, int, list[str]]:
    taken = []
    for item in items_in(level, room, "keys"):
        bit = 1 << key_index[item["id"]]
        if keys & bit == 0:
            keys |= bit
            taken.append(item["id"])
    for item in items_in(level, room, "puzzle"):
        bit = 1 << note_index[item["id"]]
        if notes & bit == 0:
            notes |= bit
            taken.append(item["id"])
    return keys, notes, taken


def solve(level: dict) -> list[dict] | None:
    rules = level["rules"]
    graph = adjacency(level)
    key_index, note_index, food_index, rest_index = collect_indexes(level)
    required = 0
    for puzzle_id in level["exit"]["requires"]:
        required |= 1 << note_index[puzzle_id]
    start_keys, start_notes, _ = apply_enter(level, level["start"], 0, 0, key_index, note_index)
    start = (level["start"], start_keys, start_notes, 0, rules["hungerStart"], rules["staminaStart"])
    queue: deque = deque([start])
    parent: dict[tuple, tuple | None] = {start: None}
    action_of: dict[tuple, dict | None] = {start: None}
    guard = 0
    found = None
    while queue:
        guard += 1
        if guard > 2_000_000:
            return None
        state = queue.popleft()
        room, keys, notes, consumed, hunger, stamina = state
        if room == level["exit"]["room"] and (notes & required) == required:
            found = state
            break
        for food in items_in(level, room, "food"):
            bit = 1 << food_index[food["id"]]
            if consumed & bit:
                continue
            nxt = (room, keys, notes, consumed | bit, min(100, hunger + food["hunger"]), stamina)
            if nxt not in parent:
                parent[nxt] = state
                action_of[nxt] = {"action": "eat", "id": food["id"]}
                queue.append(nxt)
        for rest in items_in(level, room, "rest"):
            bit = 1 << (len(food_index) + rest_index[rest["id"]])
            if consumed & bit:
                continue
            nxt = (room, keys, notes, consumed | bit, hunger, min(100, stamina + rest["stamina"]))
            if nxt not in parent:
                parent[nxt] = state
                action_of[nxt] = {"action": "rest", "id": rest["id"]}
                queue.append(nxt)
        for other, lock in graph[room]:
            if lock is not None and (keys & (1 << key_index[lock])) == 0:
                continue
            next_hunger = hunger - rules["moveHunger"]
            next_stamina = stamina - rules["moveStamina"]
            if next_hunger < 1 or next_stamina < 1:
                continue
            next_keys, next_notes, taken = apply_enter(level, other, keys, notes, key_index, note_index)
            nxt = (other, next_keys, next_notes, consumed, next_hunger, next_stamina)
            if nxt not in parent:
                parent[nxt] = state
                action_of[nxt] = {"action": "move", "to": other, "take": taken}
                queue.append(nxt)
    if found is None:
        return None
    steps = []
    cursor = found
    while parent[cursor] is not None:
        act = action_of[cursor]
        if act["action"] == "move":
            for item_id in reversed(act["take"]):
                steps.append({"action": "take", "id": item_id})
            steps.append({"action": "move", "to": act["to"]})
        else:
            steps.append(act)
        cursor = parent[cursor]
    steps.reverse()
    steps.append({"action": "exit"})
    return steps


def local_flavor_is_safe(level: dict) -> bool:
    briefing = level["briefing"]
    for room in level["rooms"]:
        if room["id"] in briefing:
            return False
    return "r0_0" not in briefing


ITEM_WORDS = {
    "small_key": ("key", "brass"),
    "vhs": ("tape", "vhs"),
    "valve": ("valve",),
    "fuse": ("fuse",),
    "almond_water": ("almond",),
    "canned_soup": ("soup",),
    "granola": ("granola",),
    "quiet_cot": ("cot",),
    "buzzing_mattress": ("mattress",),
}


def annotate_items(level: dict) -> None:
    by_id = {room["id"]: room for room in level["rooms"]}
    for room_id, contents in level["contents"].items():
        missing = []
        description = by_id[room_id]["description"].lower()
        for kind in ("keys", "puzzle", "food", "rest"):
            for item in contents[kind]:
                if item["name"].lower() not in description:
                    missing.append(item["name"])
        if missing:
            by_id[room_id]["description"] += " Left here: " + ", ".join(missing) + "."


def room_item_ids(level: dict, room_id: str) -> set[str]:
    contents = level["contents"][room_id]
    found = set()
    for kind in ("keys", "puzzle", "food", "rest"):
        for item in contents[kind]:
            found.add(item["id"])
    return found


def sanitize_room_text(level: dict) -> None:
    for room in level["rooms"]:
        present = room_item_ids(level, room["id"])
        lowered = room["description"].lower()
        for item_id, words in ITEM_WORDS.items():
            if item_id in present:
                continue
            if any(word in lowered for word in words):
                room["description"] = THEME_LINES[room["theme"]]
                break
        if not room["description"].strip():
            room["description"] = THEME_LINES[room["theme"]]


def apply_openai_flavor(level: dict, enabled: bool) -> None:
    if not enabled:
        return
    api_key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not api_key:
        print("openai flavor skipped")
        return
    room_facts = {}
    for room in level["rooms"]:
        contents = level["contents"][room["id"]]
        names = [
            item["name"]
            for kind in ("keys", "puzzle", "food", "rest")
            for item in contents[kind]
        ]
        room_facts[room["id"]] = names
    payload = {
        "model": os.environ.get("OPENAI_MODEL", "gpt-4.1-mini"),
        "temperature": 0.4,
        "messages": [
            {
                "role": "system",
                "content": (
                    "You write atmosphere for a co-op Backrooms escape. Return JSON only. "
                    "Do not give a route, compass directions, or a step-by-step solution. "
                    "For each room, mention an object only if it is listed for that room. "
                    "Empty rooms stay empty. Keep damp carpet, yellow rooms, and humming lights."
                ),
            },
            {
                "role": "user",
                "content": json.dumps(
                    {
                        "returnShape": {
                            "title": "short title",
                            "pickerLabel": "AI: short title",
                            "briefing": "four sentences with no route and no object locations",
                            "rooms": "object of room id to one sentence",
                        },
                        "objectsInRoom": room_facts,
                    }
                ),
            },
        ],
    }
    request = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            body = json.loads(response.read().decode("utf-8"))
        text = body["choices"][0]["message"]["content"]
        start = text.find("{")
        end = text.rfind("}")
        flavor = json.loads(text[start : end + 1])
    except (urllib.error.URLError, KeyError, json.JSONDecodeError, TimeoutError, ValueError):
        print("openai flavor skipped")
        return
    briefing = str(flavor.get("briefing", ""))
    if any(room["id"] in briefing for room in level["rooms"]) or "first go" in briefing.lower():
        print("openai flavor skipped")
        return
    if flavor.get("title"):
        level["title"] = str(flavor["title"])[:80]
    if flavor.get("pickerLabel"):
        level["pickerLabel"] = str(flavor["pickerLabel"])[:80]
    if briefing:
        level["briefing"] = briefing[:700]
    room_text = flavor.get("rooms") or {}
    for room in level["rooms"]:
        line = room_text.get(room["id"])
        if isinstance(line, str) and line.strip() and room["id"] not in line:
            room["description"] = line.strip()[:240]
    sanitize_room_text(level)
    annotate_items(level)
    level["flavorSource"] = "openai"
    print("openai flavor applied")


def lua_key(key: str) -> str:
    if key.isidentifier():
        return key
    return "[" + json.dumps(key) + "]"


def to_lua(value, indent: int = 0) -> str:
    pad = "  " * indent
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int) and not isinstance(value, bool):
        return str(value)
    if isinstance(value, float):
        return repr(round(value, 4))
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        if not value:
            return "{}"
        inner = ",\n".join("  " * (indent + 1) + to_lua(item, indent + 1) for item in value)
        return "{\n" + inner + "\n" + pad + "}"
    if isinstance(value, dict):
        if not value:
            return "{}"
        lines = []
        for key, item in value.items():
            lines.append("  " * (indent + 1) + f"{lua_key(str(key))} = {to_lua(item, indent + 1)}")
        return "{\n" + ",\n".join(lines) + "\n" + pad + "}"
    raise TypeError(type(value))


def generate(seed: int) -> dict:
    for offset in range(40):
        level = build_topology(random.Random(seed + offset))
        steps = solve(level)
        if steps and any(step["action"] == "eat" for step in steps) and any(step["action"] == "rest" for step in steps):
            level["solution"]["steps"] = steps
            level["seed"] = seed + offset
            if not local_flavor_is_safe(level):
                raise SystemExit("local briefing leaked a room id")
            return level
    raise SystemExit("no solvable layout in 40 seeds")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, default=1360)
    parser.add_argument("--openai", action="store_true")
    parser.add_argument("--out", type=Path, default=ROOT / "levels" / "the_yellow_static.json")
    parser.add_argument(
        "--lua",
        type=Path,
        default=ROOT / "mod" / "CustomBackroomsMap" / "levels" / "the_yellow_static.lua",
    )
    args = parser.parse_args()
    level = generate(args.seed)
    apply_openai_flavor(level, args.openai)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.lua.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(level, indent=2) + "\n", encoding="utf-8")
    args.lua.write_text("return " + to_lua(level) + "\n", encoding="utf-8")
    print(f"generated {level['id']} rooms={len(level['rooms'])} steps={len(level['solution']['steps'])}")


if __name__ == "__main__":
    main()
