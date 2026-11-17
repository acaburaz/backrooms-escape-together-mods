#!/usr/bin/env python3
"""Build a playable map for the mod from a level page of the Backrooms wiki, with OpenAI doing the combining.

Usage:
  python generator/wiki_level.py --level level-1 --entity entity-10 --object almond_water=object-1 --activate

What happens:
  1. The wiki pages are fetched into docs/lore/wiki/ (wiki_fetch.py) unless they are already there.
  2. OpenAI pulls facts out of them. Every fact carries a quote, and a fact is only kept when its
     quote is found word for word on the saved page. Kept facts go to docs/lore/wiki/<level>.facts.json.
  3. The layout, the items and the rules come from generate_level.py, which proves the map solvable.
  4. OpenAI is given the facts, the rules of the mod, the rooms and the list of lines the mod shows,
     and returns the name, the looks of the rooms, every description and every line, each with the
     ids of the facts or rules it rests on.
  5. wiki_dod.py checks the result against the definition of done. What fails is sent back to
     OpenAI, and this repeats until everything passes or --rounds is used up.
  6. The level is written to levels/<id>.json and mod/CustomBackroomsMap/levels/<id>.lua, with the
     check results in levels/<id>.dod.json. --activate also points levels/active.txt at it.

The API key is read from the OPENAI_API_KEY environment variable and is never written anywhere.
OPENAI_MODEL picks the model (default gpt-5.5).
"""
from __future__ import annotations

import argparse
import copy
import datetime
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))

import generate_level  # noqa: E402
import wiki_dod  # noqa: E402
import wiki_fetch  # noqa: E402

MODEL = os.environ.get("OPENAI_MODEL", "gpt-5.5")
SITE = "https://backrooms-wiki.wikidot.com/"
MONSTER_CLASS = "/Game/Entities/SkinStealer/BP_SkinStealer.BP_SkinStealer_C"

# How the mod plays. Lines that tell players what to do may only say what is written here.
MECHANICS = {
    "M1": "The players arrive in the elevator of Level 0. It stops early and its doors open onto this level.",
    "M2": "The level is sixteen rooms joined by open doorways. One room is behind locked doors that open for whoever carries the small key.",
    "M3": "The mod has no hunger or tiredness of its own and never makes a player pass out. Sanity and stamina are the game's own and the mod does not touch them. Food and drink are the game's items: they lie on small tables, are picked up with the game's own key and are used from the game's inventory.",
    "M4": "Three parts lie on small tables in the rooms: a tape, a valve and a fuse. The exit door opens when the group carries all three and somebody tries the door.",
    "M5": "Every two to three minutes, and each time a part is taken, the lights go out for a while. While they are out the entity comes for the nearest player. Its grab kills and the level starts again.",
    "M6": "A room with a bed is a refuge. A green lamp beside its doorway stays lit when the lights go out. While every player is inside a refuge during lights-out, the entity is no longer drawn toward them.",
    "M7": "Behind the exit door is a long hall. Looking back there undoes the distance walked. Pipes run along it and dials sit on its walls, more of them the further in. After walking far enough without looking back, light shows at the end.",
    "M8": "At the end of the hall is a small room with one sliding door and a sign over it. When the door opens and the players walk through, the same level starts again as the next loop.",
    "M9": "There are two beds: a cot, and a bare mattress with a lamp buzzing over it. They are furniture. Nothing is done on them and nobody rests or sleeps; what they are for is M6.",
    "M10": "With the lights on the entity only wanders and watches. It does not attack.",
    "M11": "Green EXIT signs hang over some doorways. They cannot be trusted. One doorway leads into a dead end; after the players have walked back out of it, it is plain wall the next time they look.",
    "M12": "A wooden crate stands in one room and creeps closer while nobody looks at it.",
    "M13": "F9 tries the exit door. Items are picked up with the game's own key and used from the game's inventory.",
    "M14": "This map is not safe. Whatever the wiki's difficulty class says, the entity kills here.",
    "M15": "A room is a square box with flat walls, a flat floor and ceiling, one ceiling lamp and open doorways. What else stands in it is its theme's props, small tables with items, and a bed if it has one.",
}

# What the fixed things in the rooms are. The mod places the game's own items, so these cannot change.
ITEMS = {
    "almond_water": "food: a bottle of the game's Almond Water",
    "canned_soup": "food: a can of the game's canned soup",
    "granola": "food: a wrapped granola square from the game",
    "vhs": "part for the exit door: the game's VHS tape",
    "valve": "part for the exit door: the game's green valve wheel",
    "fuse": "part for the exit door: the game's glass fuse",
    "small_key": "the game's small key, opens the locked room",
    "quiet_cot": "bed: a cot (a green cot with a pillow)",
    "buzzing_mattress": "bed: a bare mattress on the floor with a lamp buzzing over it",
}

# The game's own pickups keep plain names, so the prompt on screen and the thing picked up agree.
# The two beds are the mod's own furniture and can be named by the design.
ITEM_NAMES = {
    "almond_water": "Almond Water",
    "canned_soup": "Canned Soup",
    "granola": "Granola Square",
    "vhs": "VHS Tape",
    "valve": "Green Valve",
    "fuse": "Glass Fuse",
    "small_key": "Small Key",
}

TOPICS = {
    "look": ("what the level looks like: structure, surfaces, objects, lighting", 8),
    "sense": ("sounds, smells, air, damp, temperature", 3),
    "phenomenon": ("things that happen on the level: lights, shifting halls, things appearing or vanishing", 4),
    "resource": ("food, water and supplies on the level and where they turn up", 3),
    "entity": ("creatures: which live on the level, how they look and behave", 5),
    "advice": ("what wanderers are told to do or to avoid", 5),
    "entrance": ("how one arrives on this level", 2),
    "exit": ("how one leaves this level and where that leads", 1),
    "difficulty": ("the survival difficulty class and the lines under it", 1),
    "object": ("what the object pages say about an object", 2),
}

PROPS = wiki_dod.PROPS


def now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def ask(messages: list[dict]) -> dict:
    """One chat completion that has to come back as a JSON object."""
    key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not key:
        raise SystemExit("OPENAI_API_KEY is not set in the environment")
    payload = {"model": MODEL, "messages": messages, "response_format": {"type": "json_object"}}
    request = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=600) as response:
            body = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace").replace(key, "<key>")
        raise SystemExit(f"OpenAI answered {error.code}: {detail[:400]}")
    usage = body.get("usage", {})
    print(f"  openai {MODEL}: {usage.get('prompt_tokens', '?')} tokens in, {usage.get('completion_tokens', '?')} out")
    return json.loads(body["choices"][0]["message"]["content"])


# ---------------------------------------------------------------- facts

def extract_facts(pages: dict[str, str], roles: dict[str, str], rounds: int) -> list[dict]:
    """Facts with quotes that are really on the pages. roles says what each page is (level, entity, object)."""
    normal = {slug: wiki_dod.norm(text) for slug, text in pages.items()}
    kept: list[dict] = []
    seen: set[str] = set()
    rejected: list[str] = []
    dropped: list[str] = []
    system = (
        "You pull facts out of pages of the Backrooms wiki for a level designer. Return one JSON object and nothing else. "
        "Every fact has a `quote` copied character for character from the page it names: one or two whole sentences, "
        "at most 280 characters, no ellipsis, nothing added, nothing left out, nothing corrected. "
        "`claim` says the same thing in one short plain sentence and nothing more: every part of the claim must be stated "
        "in the quote itself. Pick quotes that carry the fact on their own. The only thing a claim may add is the name of "
        "the page's own subject (the level, the entity, the object) where the quote says 'it', 'they' or 'here'. "
        "Use only what the pages say."
    )
    titles = {slug: roles[slug] for slug in pages}
    has_objects = any("object page" in role for role in roles.values())
    for round_index in range(1, rounds + 1):
        counts = {topic: sum(1 for fact in kept if fact["topic"] == topic) for topic in TOPICS}
        short = {topic: need - counts[topic] for topic, (_, need) in TOPICS.items() if counts[topic] < need}
        if "object" in short and not has_objects:
            del short["object"]
        if not short:
            break
        ask_for = {topic: {"means": TOPICS[topic][0], "atLeast": missing + 2} for topic, missing in short.items()}
        user = {
            "pages": {slug: {"is": roles[slug], "text": text} for slug, text in pages.items()},
            "topicsWanted": ask_for,
            "rules": [
                "Facts about the level's look, senses, phenomena, resources, advice, entrances, exits and difficulty come from the level page.",
                "Entity facts come from the entity page, plus what the level page says about that entity.",
                "Object facts come from the object pages.",
                "Prefer facts a game level can show: what is seen, heard, found, and what happens.",
                "Skip groups, bases, people and trade.",
                "For the exit topic, quote the sentence that names the level the main exit leads to.",
            ],
            "alreadyHave": [fact["quote"] for fact in kept],
            "rejectedBecauseNotWordForWord": rejected[-20:],
            "rejectedBecauseTheQuoteDidNotSayTheWholeClaim": dropped[-30:],
            "returnShape": {"facts": [{"page": "page slug", "topic": "one of the wanted topics", "claim": "...", "quote": "..."}]},
        }
        print(f"facts round {round_index}: asking for {', '.join(f'{t} x{n}' for t, n in short.items())}")
        answer = ask([{"role": "system", "content": system}, {"role": "user", "content": json.dumps(user, ensure_ascii=False)}])
        candidates = []
        for fact in answer.get("facts", []):
            page, topic = str(fact.get("page", "")), str(fact.get("topic", ""))
            quote, claim = wiki_dod.norm(str(fact.get("quote", ""))), wiki_dod.norm(str(fact.get("claim", "")))
            if page not in normal or topic not in TOPICS or not claim:
                continue
            if len(quote) < 12 or len(quote) > 320 or quote not in normal[page]:
                rejected.append(quote)
                continue
            if quote in seen:
                continue
            seen.add(quote)
            candidates.append({"n": len(candidates) + 1, "page": page, "topic": topic, "claim": claim, "quote": quote})
        # A second reading, without the pages: does the quote alone say what the claim says?
        unsupported = set()
        if candidates:
            verdict = ask([
                {"role": "system", "content": (
                    "You check facts taken from wiki pages. For each one, read only its quote and decide whether the quote "
                    "itself states every part of the claim. The claim may name the subject of the page the quote comes from "
                    "(given in pageIs) where the quote says 'it', 'they', 'this' or 'here'. Anything else the claim says that "
                    "the quote does not say makes it unsupported. Return JSON: {\"unsupported\": [n, ...], \"why\": {\"n\": \"...\"}}."
                )},
                {"role": "user", "content": json.dumps({
                    "pageIs": titles,
                    "facts": [{"n": c["n"], "page": c["page"], "claim": c["claim"], "quote": c["quote"]} for c in candidates],
                }, ensure_ascii=False)},
            ])
            unsupported = {int(n) for n in verdict.get("unsupported", []) if str(n).isdigit()}
        for candidate in candidates:
            if candidate["n"] in unsupported:
                dropped.append(candidate["claim"])
                continue
            kept.append({"id": f"F{len(kept) + 1:02d}", "page": candidate["page"], "topic": candidate["topic"],
                         "claim": candidate["claim"], "quote": candidate["quote"]})
        print(f"  {len(kept)} facts kept; so far {len(rejected)} quotes were not word for word and {len(dropped)} claims said more than their quote")
    counts = {topic: sum(1 for fact in kept if fact["topic"] == topic) for topic in TOPICS}
    missing = [topic for topic, (_, need) in TOPICS.items() if counts[topic] < need and not (topic == "object" and not has_objects)]
    if missing:
        raise SystemExit(f"could not get enough quoted facts about: {', '.join(missing)}")
    return kept


def difficulty_of(level_text: str) -> dict:
    """The survival difficulty box as the page prints it."""
    flat = level_text.replace("\r", "")
    found = re.search(r"SURVIVAL DIFFICULTY:\s*\n\s*(\S+)\s*\n((?:\s*- [^\n]*\n)+)", flat)
    if not found:
        return {}
    lines = [line.strip()[2:].strip() for line in found.group(2).splitlines() if line.strip().startswith("- ")]
    return {"class": found.group(1), "lines": [line for line in lines if "{$" not in line]}


# ---------------------------------------------------------------- design

def room_cards(level: dict) -> list[dict]:
    cards = []
    for room in level["rooms"]:
        contents = level["contents"][room["id"]]
        holds = [item["id"] for kind in ("keys", "puzzle", "food", "rest") for item in contents[kind]]
        card = {"id": room["id"], "holds": holds}
        if room["id"] == level["start"]:
            card["note"] = "first room: the elevator lets the players out here"
        if room["id"] == level["exit"]["room"]:
            card["note"] = "last room: behind the locked doors, has the exit door"
        if contents["rest"]:
            card["refuge"] = True
        cards.append(card)
    return cards


def design_request(level: dict, facts: list[dict], wiki_title: str, entity_title: str) -> list[dict]:
    contract = wiki_dod.CONTRACT
    system = (
        "You turn pages of the Backrooms wiki into one playable co-op map for a mod of the game Backrooms: Escape Together. "
        "The mod already fixes the layout, the items and the rules. You decide what the place is called, how each room looks, "
        "what each room's description says and every line the players read, so that playing the map feels like being on the "
        "level the wiki page describes. Return one JSON object and nothing else.\n\n"
        "Hard rules:\n"
        "1. Lore comes only from the facts given. Do not invent places, names, groups, creatures, objects or numbers. "
        "Do not mention any level, entity or object the facts do not mention.\n"
        "2. Anything that tells players what to do or what will happen comes only from the mechanics given. "
        "A wiki fact that contradicts a mechanic is left out. Never say what a flashlight or any light source does.\n"
        "3. Every theme, room, item, the entity, the briefing and every text line lists in `because` the ids it rests on: "
        "F ids for facts, M ids for mechanics. A line of kind lore needs at least one F id, kind mechanic at least one M id, "
        "kind both at least one of each. A key with `needs` must cite a fact of one of those topics.\n"
        "4. No room ids, no compass directions, no routes, no hints where things are.\n"
        "5. A room description names every item the room holds, by the exact name you give that item, and names no item, "
        "food, key, tape, valve, fuse, cot, mattress or bed that the room does not hold.\n"
        "6. Write like subtitles in a quiet horror game: second person, present tense, short plain sentences, no exclamation marks. "
        "Stay inside each line's character limit. Keep every {placeholder} exactly as given.\n"
        "7. The title is the wiki's own name for the level. The entity keeps the wiki's name. Almond Water keeps the wiki's name.\n"
        "8. A room description says only what a player can see, hear, smell or feel there (mechanic M15): the theme's colours, "
        "the props of its theme, the items, the bed, the lamp, the doorways. If it mentions pipes, puddles, crates, shelves, "
        "pillars, columns or growth, the room's theme must have that prop. Nothing the mod does not build: no arches, curved "
        "walls, windows, stairs, plants other than the growth prop, vehicles, fog, offices or furniture. Every room has a lamp "
        "and doorways, so do not spend words on them; give each room one detail of its own to notice. Things to pick up stand "
        "on small tables, only beds are on the floor. Dials are in the hall behind the exit door, never in a room.\n"
        "9. The map is dangerous (M14). Do not call the place safe. The sign over the exit door must not read EXIT, because "
        "untrustworthy EXIT signs already hang in the level (M11); take a word from the facts about the way out.\n"
        "10. The mod has no hunger, no tiredness and no passing out (M3), and nobody rests or sleeps on a bed (M9). Do not "
        "write about being hungry, starving, resting, sleeping or passing out, and do not say what food or drink does: "
        "that is the game's business."
    )
    user = {
        "wikiLevelPage": wiki_title,
        "wikiEntityPage": entity_title,
        "facts": [{"id": f["id"], "topic": f["topic"], "page": f["page"], "claim": f["claim"], "quote": f["quote"]} for f in facts],
        "mechanics": MECHANICS,
        "rooms": room_cards(level),
        "items": {item_id: {"is": what, **({"name": ITEM_NAMES[item_id]} if item_id in ITEM_NAMES else {"name": "you name it"})}
                  for item_id, what in ITEMS.items()},
        "themes": {
            "howMany": "3 to 5, each used by at least two rooms; neighbouring rooms may share one",
            "fields": {
                "wall": "upper wall colour [r,g,b], each 0 to 1 (these are dark, matte surface colours: concrete is about 0.33)",
                "band": "lower wall band colour",
                "floor": "floor colour",
                "ceil": "ceiling colour",
                "trim": "skirting and door frame colour",
                "light": "lamp colour, bright, e.g. [1.0, 0.92, 0.82]",
                "power": "lamp strength 0.5 (dim) to 1.1 (bright)",
                "props": "list of 0 to 3 of: " + json.dumps(PROPS),
            },
            "note": "Rooms that hold items have less free floor: give those themes at most 2 corner props. 'says' on a text key lists words of which the line must contain at least one, so the instruction survives.",
        },
        "textKeys": {
            key: {k: spec[k] for k in ("kind", "max", "when", "vars", "needs", "says") if k in spec}
            for key, spec in contract["keys"].items()
        },
        "textLists": contract["lists"],
        "returnShape": {
            "title": "the level's name on the wiki, without the number",
            "briefing": "three or four sentences, at most 600 characters: what this place is and what the group must do",
            "themes": {"<theme name in snake_case>": {"wall": [0.3, 0.3, 0.3], "band": [], "floor": [], "ceil": [], "trim": [], "light": [], "power": 0.8, "props": []}},
            "rooms": {"<room id>": {"theme": "<theme name>", "description": "at most 170 characters"}},
            "items": {"<item id>": {"name": "only for the two beds: display name, 2 words", "clue": "only for vhs, valve and fuse: one line shown after it is taken, at most 90 characters"}},
            "entity": {"name": "the wiki's name"},
            "exitTo": "only the word Level and the number, e.g. 'Level 7', with no nickname: the level the facts say the main exit leads to",
            "text": {"<text key>": "the line", "whispers": ["four lines"]},
            "because": {
                "briefing": ["F01", "M4"], "entity": ["F.."], "themes.<name>": ["F.."], "rooms.<room id>": ["F.."],
                "items.<item id>": ["F.. or M.."], "text.<key>": ["F..", "M.."], "text.whispers": ["F.."],
            },
        },
    }
    return [{"role": "system", "content": system}, {"role": "user", "content": json.dumps(user, ensure_ascii=False)}]


def colour(value) -> list[float]:
    if not (isinstance(value, list) and len(value) == 3):
        return [0.3, 0.3, 0.3]
    return [round(min(1.0, max(0.0, float(c))), 3) for c in value]


def apply_design(base: dict, design: dict, facts: list[dict], meta: dict) -> dict:
    """The solvable base level with the names, looks and lines of the design laid over it."""
    level = copy.deepcopy(base)
    because = {str(place): [str(i) for i in ids] for place, ids in (design.get("because") or {}).items() if isinstance(ids, list)}
    level["id"] = meta["id"]
    level["title"] = str(design.get("title", "")).strip()
    level["pickerLabel"] = f"WIKI {meta['number']}: {level['title']}"
    level["briefing"] = str(design.get("briefing", "")).strip()
    level["flavorSource"] = "wiki+openai"
    level["rules"]["refuge"] = True
    level["rules"]["creeper"] = "crate"
    level["rules"]["exitPipes"] = True
    level["coop"]["rules"] = MECHANICS["M4"]
    level["themes"] = {}
    for name, theme in (design.get("themes") or {}).items():
        if not isinstance(theme, dict):
            continue
        level["themes"][str(name)] = {
            **{field: colour(theme.get(field)) for field in wiki_dod.THEME_COLOURS},
            "power": round(float(theme.get("power", 0.8)), 2) if isinstance(theme.get("power"), (int, float)) else 0.8,
            "props": [str(p) for p in theme.get("props", [])][:3] if isinstance(theme.get("props"), list) else [],
        }
    rooms = design.get("rooms") or {}
    for room in level["rooms"]:
        given = rooms.get(room["id"]) or {}
        room["theme"] = str(given.get("theme", ""))
        room["description"] = str(given.get("description", "")).strip()
    items = design.get("items") or {}
    for contents in level["contents"].values():
        for kind in ("keys", "puzzle", "food", "rest"):
            for item in contents[kind]:
                given = items.get(item["id"]) or {}
                if item["id"] in ITEM_NAMES:
                    item["name"] = ITEM_NAMES[item["id"]]
                elif str(given.get("name", "")).strip():
                    item["name"] = str(given["name"]).strip()
                if kind == "puzzle":
                    item["clue"] = str(given.get("clue", "")).strip() or item["clue"]
    entity = design.get("entity") or {}
    level["monsters"] = [{
        "id": "entity", "name": str(entity.get("name", "")).strip(), "patrol": base["monsters"][0]["patrol"],
        "damage": base["monsters"][0]["damage"], "visualClass": MONSTER_CLASS,
    }]
    if "entity" in because:
        because["monster"] = because.pop("entity")
    text = {}
    for key, value in (design.get("text") or {}).items():
        if isinstance(value, list):
            text[str(key)] = [str(line).strip() for line in value]
        else:
            text[str(key)] = str(value).strip()
    level["text"] = text
    used = sorted({i for ids in because.values() for i in ids})
    level["wiki"] = {
        "site": SITE,
        "level": meta["level"],
        "entity": meta["entity"],
        "objects": meta["objects"],
        "pages": meta["pages"],
        "licence": wiki_fetch.LICENCE,
        "credit": "Lore, names and descriptions are adapted from The Backrooms wiki (" + SITE + "), pages: "
                  + ", ".join(SITE + slug for slug in meta["pages"]) + ". Licensed CC BY-SA 3.0.",
        "difficulty": meta["difficulty"],
        "exitTo": str(design.get("exitTo", "")).strip(),
        "model": MODEL,
        "generated": now(),
        "mechanics": MECHANICS,
        "facts": [fact for fact in facts if fact["id"] in used],
        "because": because,
    }
    return level


def lua_copy(level: dict) -> dict:
    """What the mod needs. The quotes and citations stay in the JSON."""
    slim = copy.deepcopy(level)
    wiki = slim["wiki"]
    slim["wiki"] = {key: wiki[key] for key in ("site", "level", "entity", "licence", "credit", "difficulty", "exitTo")}
    return slim


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--level", required=True, help="wiki page of the level, e.g. level-1")
    parser.add_argument("--entity", required=True, help="wiki page of the entity the game's Skin Stealer stands for, e.g. entity-10")
    parser.add_argument("--object", action="append", default=[], metavar="ITEM=PAGE",
                        help="wiki page for one of the game's items, e.g. almond_water=object-1")
    parser.add_argument("--seed", type=int, default=1360, help="layout seed for generate_level.py")
    parser.add_argument("--rounds", type=int, default=6, help="how many times OpenAI may be sent back to fix failed checks")
    parser.add_argument("--id", default=None, help="file name of the level, default from the wiki title")
    parser.add_argument("--refresh", action="store_true", help="fetch the wiki pages again and extract the facts again")
    parser.add_argument("--activate", action="store_true", help="make the mod load this level (levels/active.txt)")
    args = parser.parse_args()

    objects = dict(pair.split("=", 1) for pair in args.object)
    for item_id in objects:
        if item_id not in ITEMS:
            raise SystemExit(f"--object {item_id}: the mod has no such item. It has: {', '.join(ITEMS)}")
    roles = {args.level: "the level page", args.entity: "the entity page"}  # filled in with titles below
    for item_id, slug in objects.items():
        roles[slug] = f"the object page for the item {item_id}"
    pages = {slug: wiki_fetch.load(slug, args.refresh) for slug in roles}
    index = json.loads((wiki_fetch.WIKI_DIR / "index.json").read_text(encoding="utf-8"))
    page_meta = {slug: {key: index[slug][key] for key in ("url", "title", "fetched")} for slug in roles}
    wiki_title = page_meta[args.level]["title"]
    number = re.search(r"Level [\d.]+", wiki_title)
    number = number.group(0).upper() if number else args.level.upper()
    level_id = args.id or re.sub(r"[^a-z0-9]+", "_", wiki_title.lower()).strip("_")
    print(f"{wiki_title} -> {level_id}")
    for slug in roles:
        roles[slug] += ": " + page_meta[slug]["title"]

    facts_path = wiki_fetch.WIKI_DIR / f"{args.level}.facts.json"
    if facts_path.exists() and not args.refresh:
        stored = json.loads(facts_path.read_text(encoding="utf-8"))
        facts = stored["facts"] if stored.get("pages") == sorted(roles) else None
    else:
        facts = None
    if facts is None:
        facts = extract_facts(pages, roles, rounds=4)
        facts_path.write_text(json.dumps({"pages": sorted(roles), "model": MODEL, "extracted": now(), "facts": facts},
                                         indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    print(f"{len(facts)} quoted facts in {facts_path.relative_to(ROOT)}")

    base = generate_level.generate(args.seed)
    meta = {
        "id": level_id, "number": number, "level": args.level, "entity": args.entity, "objects": objects,
        "pages": page_meta, "difficulty": difficulty_of(pages[args.level]),
    }
    sources = {slug: (wiki_fetch.WIKI_DIR / f"{slug}.md").read_text(encoding="utf-8") for slug in roles}
    messages = design_request(base, facts, wiki_title, page_meta[args.entity]["title"])
    level, results = None, []
    for round_index in range(1, args.rounds + 1):
        print(f"design round {round_index}")
        design = ask(messages)
        level = apply_design(base, design, facts, meta)
        level["wiki"]["rounds"] = round_index
        results = wiki_dod.check(level, sources)
        failed = [result for result in results if not result["ok"]]
        for result in results:
            print(("  PASS " if result["ok"] else "  FAIL ") + result["id"] + "  " + (result["detail"] if not result["ok"] else result["what"]))
        if not failed:
            break
        messages.append({"role": "assistant", "content": json.dumps(design, ensure_ascii=False)})
        messages.append({"role": "user", "content": json.dumps({
            "theMapFailedTheseChecks": [{"check": result["what"], "problems": result["detail"]} for result in failed],
            "do": "Return the whole JSON object again with these problems fixed. Keep everything that was not named as a problem.",
        }, ensure_ascii=False)})

    out_json = ROOT / "levels" / f"{level_id}.json"
    out_lua = ROOT / "mod" / "CustomBackroomsMap" / "levels" / f"{level_id}.lua"
    out_dod = ROOT / "levels" / f"{level_id}.dod.json"
    out_json.write_text(json.dumps(level, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    out_dod.write_text(json.dumps({"level": level_id, "checked": now(), "results": results}, indent=2, ensure_ascii=False) + "\n",
                       encoding="utf-8", newline="\n")
    failed = [result for result in results if not result["ok"]]
    if failed:
        print(f"{len(failed)} checks still fail after {args.rounds} rounds. The level was written to {out_json.relative_to(ROOT)} for inspection, not to the mod.")
        return 1
    out_lua.write_text("return " + generate_level.to_lua(lua_copy(level)) + "\n", encoding="utf-8", newline="\n")
    if args.activate:
        (out_lua.parent / "active.txt").write_text(out_lua.name + "\n", encoding="utf-8", newline="\n")
    print(f"wiki definition of done passed in {level['wiki']['rounds']} round(s)")
    print(f"wrote {out_json.relative_to(ROOT)}, {out_lua.relative_to(ROOT)}" + (" and made it the active level" if args.activate else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
