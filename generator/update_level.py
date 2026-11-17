#!/usr/bin/env python3
"""Bring a level file made before version 0.3.0 up to date without rewriting its wording.

Until 0.3.0 the mod kept a hunger and a stamina of its own: rooms cost some of both, food and beds
gave them back, and at zero the players passed out and woke in the first room. That is gone. Sanity
and stamina are the game's, and the food on the tables is the game's own, used from its inventory.

    python generator/update_level.py levels/<id>.json [...]

For each level this takes out what belonged to the old rule (the numbers in `rules` and on food and
beds, the seven lines about eating, resting and passing out, the eat and rest steps of the stored
solution), solves the level again, and writes the JSON and the mod's .lua. A wiki level also gets
the current rules of the mod (wiki.mechanics) and is checked against the definition of done; its
.lua is only written when every check passes. No wording is changed and OpenAI is not called.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import generate_level
import wiki_dod
import wiki_level

ROOT = Path(__file__).resolve().parents[1]
OLD_RULES = ("hungerStart", "staminaStart", "moveHunger", "moveStamina")
OLD_LINES = ("wake", "collapse", "hungry", "tired", "eat", "restQuiet", "restLoud")
OLD_ITEM_FIELDS = ("hunger", "stamina", "callsMonster")


def update(level: dict) -> list[str]:
    """Changes the level in place. Returns what was done, for the report."""
    done = []
    rules = level.setdefault("rules", {})
    for name in OLD_RULES:
        if rules.pop(name, None) is not None:
            done.append(f"rules.{name} removed")
    if level.get("coop", {}).pop("sharedVitals", None) is not None:
        done.append("coop.sharedVitals removed")
    food_rooms, food_items = set(), set()
    for room_id, contents in level["contents"].items():
        for kind in ("food", "rest"):
            for item in contents[kind]:
                for field in OLD_ITEM_FIELDS:
                    if item.pop(field, None) is not None:
                        done.append(f"{item['id']}.{field} removed")
                if kind == "food":
                    food_rooms.add(room_id)
                    food_items.add(item["id"])
    text = level.get("text") or {}
    for key in OLD_LINES:
        if text.pop(key, None) is not None:
            done.append(f"text.{key} removed")
    wiki = level.get("wiki")
    if isinstance(wiki, dict):
        because = wiki.get("because", {})
        for key in OLD_LINES:
            because.pop(f"text.{key}", None)
        # M3 used to be the hunger rule and now only speaks of the game's food.
        for place, ids in because.items():
            kind, _, name = place.partition(".")
            about_food = (kind == "rooms" and name in food_rooms) or (kind == "items" and name in food_items)
            if "M3" in ids and kind in ("rooms", "items") and not about_food:
                ids.remove("M3")
                done.append(f"{place} no longer cites M3")
        if wiki.get("mechanics") != wiki_level.MECHANICS:
            wiki["mechanics"] = dict(wiki_level.MECHANICS)
            done.append("wiki.mechanics brought up to date")
    steps = generate_level.solve(level)
    if steps is None:
        raise SystemExit(f"{level['id']}: no way from the start to the exit")
    if steps != level.get("solution", {}).get("steps"):
        level["solution"] = {"steps": steps}
        done.append(f"solution solved again ({len(steps)} steps)")
    return done


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    status = 0
    for name in sys.argv[1:]:
        path = Path(name)
        level = json.loads(path.read_text(encoding="utf-8"))
        done = update(level)
        print(f"{level['id']}: " + ("; ".join(done) if done else "already up to date"))
        out_lua = ROOT / "mod" / "CustomBackroomsMap" / "levels" / f"{level['id']}.lua"
        path.write_text(json.dumps(level, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
        if isinstance(level.get("wiki"), dict):
            results = wiki_dod.check(level)
            failed = [result for result in results if not result["ok"]]
            out_dod = path.with_name(f"{level['id']}.dod.json")
            out_dod.write_text(json.dumps({"level": level["id"], "checked": wiki_level.now(), "results": results}, indent=2,
                                          ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
            for result in failed:
                print(f"  FAIL {result['id']}  {result['detail']}")
            if failed:
                print(f"  {len(failed)} checks fail. {out_lua.name} was not written.")
                status = 1
                continue
            print(f"  wiki definition of done passed ({len(results)} checks)")
            lua = wiki_level.lua_copy(level)
        else:
            lua = level
        out_lua.write_text("return " + generate_level.to_lua(lua) + "\n", encoding="utf-8", newline="\n")
        print(f"  wrote {path.name} and {out_lua.name}")
    return status


if __name__ == "__main__":
    sys.exit(main())
