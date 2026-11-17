#!/usr/bin/env python3
"""Definition of done for a map built from a Backrooms wiki level page.

Usage: python generator/wiki_dod.py levels/level_1_habitable_zone.json

A level page on the wiki has the same parts every time: a survival difficulty class, a description,
the entities that live there, and its entrances and exits. The map is done when each of those parts
is in the map, every line the players read rests on a quote from the wiki or on a rule of the mod,
and the map can be played to the end. WIKI.md lists the checks in words.

Prints one line per check and ends with "wiki definition of done passed" or the number that failed.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))

import generate_level  # noqa: E402
import wiki_fetch  # noqa: E402

CONTRACT = json.loads((Path(__file__).resolve().parent / "text_keys.json").read_text(encoding="utf-8"))
# Furniture halls.lua can build for a theme (its DECOR table), and what each looks like.
PROPS = {
    "pillar": "a square concrete pillar in one corner of the room",
    "column": "a round concrete column in one corner of the room",
    "crates": "wooden crates stacked on the floor in one corner",
    "shelf": "a metal storage shelf with crates on it in one corner",
    "pipes": "two pipes running under the ceiling",
    "puddle": "standing water on the floor",
    "growth": "flat green growth spreading over the floor and the foot of the walls",
    "debris": "small piles of debris on the floor: pieces of wood, packing material and metal",
}
# Things a room description may not claim to show, because the mod builds flat-walled rooms and the props above.
NOT_BUILT = ("arch", "arches", "arched", "curve", "curves", "curved", "window", "windows", "stairs", "stairway", "staircase",
             "tree", "trees", "vines", "flowers", "fog", "mist", "car", "cars", "office", "desk", "desks",
             "dial", "dials", "gauge", "gauges", "valves", "machine", "machines", "generator")
THEME_COLOURS = ("wall", "band", "floor", "ceil", "trim", "light")
TOPICS = ("look", "sense", "phenomenon", "resource", "entity", "advice", "entrance", "exit", "difficulty", "object")
# Words that give an item away. A room may only use them when it holds that item.
ITEM_WORDS = {
    "small_key": ("key",),
    "vhs": ("tape", "vhs", "cassette"),
    "valve": ("valve",),
    "fuse": ("fuse",),
    "almond_water": ("almond",),
    "canned_soup": ("soup",),
    "granola": ("granola",),
}
REST_WORDS = ("cot", "mattress", "bed")
COMPASS = ("north", "south", "east", "west")
# The flashlight's effect on the Skin Stealer is untested on this floor, and the wiki's advice about light
# is about other entities. So no line may tell players what a light does.
LIGHT_ADVICE = ("flashlight", "torch", "light source")
# Capitalised words the mod itself uses.
OWN_WORDS = {"loop", "exit", "f9", "level", "wiki", "tab"}
# What the game's own items are called. The mod places them, so their names are not inventions.
GAME_WORDS = {"canned", "soup", "granola", "square", "vhs", "tape", "valve", "wheel", "fuse", "key", "cot", "mattress",
              "glass", "green", "small", "wrapped", "quiet", "buzzing", "brass"}


def norm(text: str) -> str:
    """Same text with typographic quotes and dashes flattened and whitespace collapsed."""
    table = {"\u2018": "'", "\u2019": "'", "\u201c": '"', "\u201d": '"', "\u2013": "-", "\u2014": "-", "\u2026": "...", "\xa0": " "}
    for old, new in table.items():
        text = text.replace(old, new)
    return re.sub(r"\s+", " ", text).strip()


def load_sources(level: dict) -> dict[str, str]:
    sources = {}
    for slug in level.get("wiki", {}).get("pages", {}):
        path = wiki_fetch.WIKI_DIR / (slug + ".md")
        if path.exists():
            text = path.read_text(encoding="utf-8")
            sources[slug] = text
    return sources


def page_name(title: str) -> str:
    """'Entity 10 - "Skin-Stealer"' -> 'Skin-Stealer'."""
    found = re.search(r'"([^"]+)"', norm(title))
    return found.group(1).strip() if found else title.strip()


def all_lines(level: dict) -> list[tuple[str, str]]:
    """Every string a player can read, with the place it comes from."""
    lines = [("title", level["title"]), ("briefing", level["briefing"])]
    for room in level["rooms"]:
        lines.append((f"rooms.{room['id']}", room["description"]))
    for room_id, contents in level["contents"].items():
        for kind in ("keys", "puzzle", "food", "rest"):
            for item in contents[kind]:
                lines.append((f"items.{item['id']}", item["name"]))
                if item.get("clue"):
                    lines.append((f"items.{item['id']}.clue", item["clue"]))
    for monster in level.get("monsters", []):
        lines.append(("monster", monster["name"]))
    for key, value in level.get("text", {}).items():
        if isinstance(value, list):
            for index, line in enumerate(value):
                lines.append((f"text.{key}[{index + 1}]", line))
        else:
            lines.append((f"text.{key}", value))
    return lines


def check(level: dict, sources: dict[str, str] | None = None) -> list[dict]:
    """Every check as {id, ok, what, detail}. detail says what is wrong when ok is false."""
    results: list[dict] = []

    def add(check_id: str, what: str, problems: list[str]) -> None:
        results.append({"id": check_id, "ok": not problems, "what": what, "detail": "; ".join(problems[:12])})

    wiki = level.get("wiki") or {}
    sources = sources if sources is not None else load_sources(level)
    source_norm = {slug: norm(text) for slug, text in sources.items()}
    everything = " ".join(source_norm.values())
    everything_lower = everything.lower()
    facts = {fact["id"]: fact for fact in wiki.get("facts", [])}
    because = wiki.get("because", {})
    mechanics = wiki.get("mechanics", {})
    level_slug = wiki.get("level", "")
    level_text = source_norm.get(level_slug, "")

    def topics_of(place: str) -> set[str]:
        return {facts[i]["topic"] for i in because.get(place, []) if i in facts}

    def cites(place: str) -> tuple[list[str], list[str]]:
        ids = because.get(place, [])
        return [i for i in ids if i in facts], [i for i in ids if i in mechanics]

    # --- W1: the pages are saved, with where they came from and their licence ---
    problems = []
    if not level_slug:
        problems.append("the level does not say which wiki page it is built from")
    for slug in wiki.get("pages", {}):
        text = sources.get(slug)
        if text is None:
            problems.append(f"docs/lore/wiki/{slug}.md is missing")
        elif "url: https://backrooms-wiki.wikidot.com/" not in text[:400] or "licence:" not in text[:600]:
            problems.append(f"docs/lore/wiki/{slug}.md has no url or licence header")
    if level_slug and level_slug not in wiki.get("pages", {}):
        problems.append("the level page is not among the saved pages")
    if "CC BY-SA" not in str(wiki.get("licence", "")) or "backrooms-wiki.wikidot.com" not in str(wiki.get("credit", "")):
        problems.append("the level carries no licence and credit line for the wiki")
    add("W1", "Sources: every wiki page used is saved with its url and licence, and the map credits the wiki", problems)

    # --- W2: every fact is a quote that is really on its page ---
    problems = []
    if len(facts) < 20:
        problems.append(f"only {len(facts)} facts")
    for fact in facts.values():
        page = source_norm.get(fact.get("page", ""))
        if page is None:
            problems.append(f"{fact['id']}: page {fact.get('page')} is not saved")
        elif norm(fact.get("quote", "")) not in page or len(norm(fact.get("quote", ""))) < 12:
            problems.append(f"{fact['id']}: quote is not on {fact['page']}")
        if fact.get("topic") not in TOPICS:
            problems.append(f"{fact['id']}: unknown topic {fact.get('topic')}")
    add("W2", "Facts: every fact the map rests on is a word-for-word quote from a saved page", problems)

    # --- W3: the map is called what the wiki calls the level ---
    problems = []
    page_title = norm(wiki.get("pages", {}).get(level_slug, {}).get("title", ""))
    title = norm(level.get("title", ""))
    number = re.search(r"Level [\d.]+", page_title)
    if not title or (title.lower() not in level_text.lower() and title.lower() not in page_title.lower()
                     and page_name(page_title).lower() not in title.lower()):
        problems.append(f"title {title!r} is not a name the page uses ({page_title!r})")
    if number and number.group(0).lower() not in norm(level.get("pickerLabel", "")).lower():
        problems.append(f"pickerLabel does not say {number.group(0)}")
    add("W3", "Name: the map carries the wiki's own name and number for the level", problems)

    # --- W4: survival difficulty ---
    problems = []
    difficulty = wiki.get("difficulty") or {}
    if not re.fullmatch(r"[\w.?+-]+", str(difficulty.get("class", ""))):
        problems.append("no survival difficulty class recorded")
    elif f"SURVIVAL DIFFICULTY: {difficulty['class']}" not in level_text:
        problems.append(f"the page does not say SURVIVAL DIFFICULTY: {difficulty['class']}")
    for line in difficulty.get("lines", []):
        if norm(line) not in level_text:
            problems.append(f"difficulty line not on the page: {line!r}")
    add("W4", "Survival difficulty: the class and its lines are recorded as the page gives them", problems)

    # --- W5: description -> the look of the rooms ---
    problems = []
    themes = level.get("themes") or {}
    used = {room["theme"] for room in level["rooms"]}
    if len(themes) < 3:
        problems.append(f"{len(themes)} themes, need at least 3")
    for name, theme in themes.items():
        for field in THEME_COLOURS:
            value = theme.get(field)
            if not (isinstance(value, list) and len(value) == 3 and all(isinstance(c, (int, float)) and 0 <= c <= 1 for c in value)):
                problems.append(f"themes.{name}.{field} is not three numbers from 0 to 1")
        if not (isinstance(theme.get("power"), (int, float)) and 0.3 <= theme["power"] <= 1.3):
            problems.append(f"themes.{name}.power must be 0.3 to 1.3")
        for prop in theme.get("props", []):
            if prop not in PROPS:
                problems.append(f"themes.{name} asks for unknown prop {prop}")
        if not topics_of(f"themes.{name}") & {"look", "sense"}:
            problems.append(f"themes.{name} cites no fact about how the level looks")
        if name not in used:
            problems.append(f"themes.{name} is used by no room")
    looks = set()
    for room in level["rooms"]:
        place = f"rooms.{room['id']}"
        if room["theme"] not in themes:
            problems.append(f"{place} uses theme {room['theme']}, which the level does not define")
        if not cites(place)[0]:
            problems.append(f"{place} description cites no wiki fact")
        looks |= {i for i in because.get(place, []) if i in facts and facts[i]["topic"] in ("look", "sense")}
        looks |= {i for i in because.get(f"themes.{room['theme']}", []) if i in facts and facts[i]["topic"] in ("look", "sense")}
    if len(looks) < 5:
        problems.append(f"rooms and themes rest on {len(looks)} different look/sense facts, need at least 5")
    add("W5", "Description: the rooms look and read the way the page describes the level", problems)

    # --- W6: entities ---
    problems = []
    monsters = level.get("monsters") or []
    entity_slug = wiki.get("entity", "")
    entity_name = page_name(wiki.get("pages", {}).get(entity_slug, {}).get("title", ""))
    if not monsters:
        problems.append("no entity on the map")
    else:
        if not entity_name or monsters[0]["name"].lower() != entity_name.lower():
            problems.append(f"the entity is called {monsters[0]['name']!r}, the wiki page calls it {entity_name!r}")
        if entity_name and entity_name.lower() not in level_text.lower():
            problems.append(f"the level page does not list {entity_name} among its entities")
        if "entity" not in topics_of("monster"):
            problems.append("the entity cites no entity fact")
    add("W6", "Entities: the map's entity is one the page lists for this level, under the wiki's name", problems)

    # --- W7: resources ---
    problems = []
    object_pages = wiki.get("objects", {})
    names = {}
    for contents in level["contents"].values():
        for kind in ("keys", "puzzle", "food", "rest"):
            for item in contents[kind]:
                names[item["id"]] = item["name"]
                if not cites(f"items.{item['id']}")[0] and not cites(f"items.{item['id']}")[1]:
                    problems.append(f"items.{item['id']} cites nothing")
    for item_id, slug in object_pages.items():
        want = page_name(wiki.get("pages", {}).get(slug, {}).get("title", ""))
        if names.get(item_id, "").lower() != want.lower():
            problems.append(f"{item_id} is called {names.get(item_id)!r}, the wiki page calls it {want!r}")
        if want and want.lower() not in level_text.lower():
            problems.append(f"the level page does not mention {want}")
    add("W7", "Resources: what there is to eat and drink is named as the wiki names it", problems)

    # --- W8: entrances and exits ---
    problems = []
    exit_to = str(wiki.get("exitTo", ""))
    if "entrance" not in topics_of("text.intro1"):
        problems.append("the opening line cites no entrance fact")
    if not re.fullmatch(r"Level [\d.]+", exit_to):
        problems.append(f"exitTo is {exit_to!r}, expected 'Level <number>'")
    else:
        exit_facts = [facts[i] for i in because.get("text.epiSign", []) if i in facts and facts[i]["topic"] == "exit"]
        if not any(exit_to in norm(fact["quote"]) for fact in exit_facts):
            problems.append(f"no cited exit fact quotes the page saying the level leads to {exit_to}")
        if norm(level.get("text", {}).get("epiSign", "")).upper() != exit_to.upper():
            problems.append("the sign at the end does not name the level the exit leads to")
    add("W8", "Entrances and exits: you arrive the way the page says and the way out leads where the page says", problems)

    # --- W9: every line rests on a fact or a rule ---
    problems = []
    text = level.get("text") or {}
    for key, spec in CONTRACT["keys"].items():
        line = text.get(key)
        place = f"text.{key}"
        if not isinstance(line, str) or not line.strip():
            problems.append(f"{place} is missing")
            continue
        if len(line) > spec["max"]:
            problems.append(f"{place} is {len(line)} characters, at most {spec['max']}")
        for var in spec.get("vars", []):
            if "{" + var + "}" not in line:
                problems.append(f"{place} lost its {{{var}}}")
        for stray in re.findall(r"\{(\w+)\}", line):
            if stray not in spec.get("vars", []):
                problems.append(f"{place} has an unknown {{{stray}}}")
        fact_ids, rule_ids = cites(place)
        unknown = [i for i in because.get(place, []) if i not in facts and i not in mechanics]
        if unknown:
            problems.append(f"{place} cites unknown ids {unknown}")
        if spec["kind"] in ("lore", "both") and not fact_ids:
            problems.append(f"{place} must cite a wiki fact")
        if spec["kind"] in ("mechanic", "both") and not rule_ids:
            problems.append(f"{place} must cite a rule of the mod")
        says = spec.get("says")
        if says and not any(word in line.lower() for word in says):
            problems.append(f"{place} must keep its instruction: it has to contain one of {says}")
        needs = spec.get("needs")
        if needs and any(fact["topic"] in needs for fact in facts.values()) and not topics_of(place) & set(needs):
            problems.append(f"{place} must cite a fact about {' or '.join(needs)}")
    for key, spec in CONTRACT["lists"].items():
        lines = text.get(key)
        place = f"text.{key}"
        if not isinstance(lines, list) or len(lines) != spec["count"]:
            problems.append(f"{place} must be a list of {spec['count']} lines")
            continue
        for line in lines:
            if not isinstance(line, str) or not line.strip() or len(line) > spec["max"]:
                problems.append(f"{place} has an empty or too long line")
        if not cites(place)[0]:
            problems.append(f"{place} must cite a wiki fact")
    for key in text:
        if key not in CONTRACT["keys"] and key not in CONTRACT["lists"]:
            problems.append(f"text.{key} is not a line the mod reads")
    if isinstance(text.get("loop"), str) and not text["loop"].startswith("LOOP {n}"):
        problems.append("text.loop must start with 'LOOP {n}'")
    sign = str(text.get("exitSign", ""))
    if sign and (sign != sign.upper() or " " in sign.strip()):
        problems.append("text.exitSign must be one word in capitals")
    if sign and sign.lower() not in str(text.get("objectiveExit", "")).lower():
        problems.append("text.objectiveExit must use the word on the exit sign")
    if len(level.get("briefing", "")) > 600 or not cites("briefing")[0]:
        problems.append("briefing must be at most 600 characters and cite wiki facts")
    add("W9", "Grounding: every line the players read cites a wiki quote, a rule of the mod, or both, as its kind asks", problems)

    # --- W10: nothing invented ---
    problems = []
    allowed = set(OWN_WORDS) | GAME_WORDS
    for rule in mechanics.values():
        allowed |= {word.lower() for word in re.findall(r"[A-Za-z][A-Za-z'-]+", rule)}
    for place, line in all_lines(level):
        flat = norm(line)
        for ref in re.findall(r"\b(?:Level|Entity|Object) [\d.]*\d", flat):
            if ref.lower() not in everything_lower:
                problems.append(f"{place} names {ref}, which the saved pages do not")
        # A capital letter in the middle of a sentence marks a name.
        for found in re.finditer(r"(?<=[a-z,;] )([A-Z][a-z]+(?:[-'][A-Za-z]+)*)", flat):
            word = found.group(1)
            if word.lower() not in allowed and not re.search(r"\b" + re.escape(word.lower()) + r"\b", everything_lower):
                problems.append(f"{place} uses the name {word!r}, which is on none of the saved pages")
        # The exit sign, the HUD word and the last sign are single words in capitals. One that is on no page is made up.
        if place in ("text.exitSign", "text.hudHunt", "text.epiSign"):
            for word in re.findall(r"\b[A-Z]{4,}\b", flat):
                if word.lower() not in allowed and not re.search(r"\b" + re.escape(word.lower()) + r"\b", everything_lower):
                    problems.append(f"{place} uses the word {word!r}, which is on none of the saved pages")
        for bad in LIGHT_ADVICE:
            if bad in flat.lower():
                problems.append(f"{place} gives advice about a {bad}; what light does here is untested")
    add("W10", "Nothing invented: no level, entity, object or name appears that the saved pages do not have", problems)

    # --- P1: the map can be played to the end ---
    problems = []
    steps = generate_level.solve(level)
    if not steps:
        problems.append("the solver finds no way from the start to the exit")
    else:
        actions = [step["action"] for step in steps]
        if "eat" not in actions or "rest" not in actions:
            problems.append("the shortest way out needs no food or no rest, so they do not matter")
        if steps != level.get("solution", {}).get("steps"):
            problems.append("the stored solution is not the one the solver finds")
    exit_room = next((room for room in level["rooms"] if room["id"] == level["exit"]["room"]), None)
    width = max(room["x"] for room in level["rooms"]) + 1
    if exit_room is None or exit_room["x"] != width - 1:
        problems.append("the exit room is not on the east edge, where the mod puts the exit door")
    if not level.get("rules", {}).get("refuge"):
        problems.append("rules.refuge is off, but the lines talk about refuges")
    add("P1", "Playable: a route from the elevator to the exit exists, and it needs both food and rest", problems)

    # --- P2: lines give nothing away and say nothing false ---
    problems = []
    room_ids = [room["id"] for room in level["rooms"]]
    for place, line in all_lines(level):
        low = line.lower()
        if any(room_id in low for room_id in room_ids):
            problems.append(f"{place} contains a room id")
        if place.startswith("rooms.") or place == "briefing":
            for word in COMPASS:
                if re.search(r"\b" + word + r"\b", low):
                    problems.append(f"{place} gives a compass direction")
    for place, line in all_lines(level):
        if place.startswith("items.") or place == "monster":
            continue
        if re.search(r"\b(is|are|stays?|feels?|seems?) safe\b|\bsafe and secure\b", line.lower()) and place != "text.refuge":
            problems.append(f"{place} calls the place safe, and on this map the entity kills")
    if str(level.get("text", {}).get("exitSign", "")).strip().upper() == "EXIT":
        problems.append("text.exitSign is EXIT, the same word as the signs that cannot be trusted")
    for room in level["rooms"]:
        low = room["description"].lower()
        for word in NOT_BUILT:
            if re.search(r"\b" + word + r"\b", low):
                problems.append(f"rooms.{room['id']} describes a {word}, which the mod does not build")
        props = (level.get("themes", {}).get(room["theme"]) or {}).get("props", [])
        for prop, words in (("pipes", ("pipe", "pipes")), ("puddle", ("puddle", "puddles")), ("growth", ("growth", "greenery", "overgrown", "verdant")),
                            ("crates", ("crate", "crates")), ("shelf", ("shelf", "shelves", "shelving")), ("pillar", ("pillar", "pillars")),
                            ("column", ("column", "columns")),
                            ("debris", ("litter", "litters", "littered", "scrap", "scraps", "rubble", "debris"))):
            if any(re.search(r"\b" + word + r"\b", low) for word in words):
                stands_in = {"crates": ("crates", "shelf"), "pillar": ("pillar", "column"), "column": ("column", "pillar")}.get(prop, (prop,))
                if not any(p in props for p in stands_in):
                    problems.append(f"rooms.{room['id']} mentions {words[-1]}, but its theme {room['theme']} has no {prop} prop")
        # Things to pick up stand on small tables; only beds are on the floor.
        for item in [i for kind in ("keys", "puzzle", "food") for i in level["contents"][room["id"]][kind]]:
            for sentence in re.split(r"(?<=[.!?])\s+", room["description"]):
                if item["name"].lower() in sentence.lower() and re.search(r"\bon the (floor|ground|concrete)\b", sentence.lower()):
                    problems.append(f"rooms.{room['id']} puts the {item['name']} on the floor; things to pick up stand on small tables")
        if len(room["description"]) > 170:
            problems.append(f"rooms.{room['id']} description is {len(room['description'])} characters, at most 170")
        contents = level["contents"][room["id"]]
        here = {item["id"]: item for kind in ("keys", "puzzle", "food", "rest") for item in contents[kind]}
        for item_id, words in ITEM_WORDS.items():
            if item_id not in here and any(re.search(r"\b" + word + r"s?\b", low) for word in words):
                problems.append(f"rooms.{room['id']} mentions the {item_id.replace('_', ' ')}, which is not in that room")
        if not contents["rest"] and any(re.search(r"\b" + word + r"s?\b", low) for word in REST_WORDS):
            problems.append(f"rooms.{room['id']} mentions somewhere to rest, and has none")
        for item in here.values():
            if item["name"].lower() not in low:
                problems.append(f"rooms.{room['id']} holds the {item['name']} and does not mention it by that name")
    add("P2", "Honest lines: no room ids or directions, a room only mentions what is in it and what the mod builds, and nothing calls the map safe", problems)

    # --- P3: the mod reads exactly these lines ---
    problems = []
    halls = (ROOT / "mod" / "CustomBackroomsMap" / "Scripts" / "halls.lua").read_text(encoding="utf-8")
    read = set(re.findall(r'\bL\("(\w+)"', halls)) | set(re.findall(r'\bLT\(level, "(\w+)"', halls))
    wanted = set(CONTRACT["keys"])
    if read != wanted:
        problems.append(f"halls.lua reads {sorted(read - wanted)} beyond the contract and never reads {sorted(wanted - read)}")
    if "G.level.text.whispers" not in halls:
        problems.append("halls.lua does not read text.whispers")
    add("P3", "Mod contract: halls.lua reads exactly the lines listed in generator/text_keys.json", problems)

    return results


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    level = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    results = check(level)
    failed = 0
    for result in results:
        print(("PASS " if result["ok"] else "FAIL ") + result["id"] + "  " + result["what"])
        if not result["ok"]:
            failed += 1
            print("       " + result["detail"])
    if failed:
        print(f"{failed} of {len(results)} checks failed")
        return 1
    print("wiki definition of done passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
