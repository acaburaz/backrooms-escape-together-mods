"""Write the lore documents under docs/lore from the saved wiki pages and facts.

    python generator/lore_doc.py

docs/lore/README.md           what is saved, from where, when, under which licence
docs/lore/<level id>.md       one lore sheet per generated wiki level: the quoted facts by subject, and
                              every line of the map with the facts and rules it rests on

Nothing is fetched and nothing is asked of OpenAI here; the documents are a readable view of
docs/lore/wiki/*.md, docs/lore/wiki/<level>.facts.json and levels/<level id>.json. Run it again after
fetching pages or making a level.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import wiki_fetch  # noqa: E402

LORE = ROOT / "docs" / "lore"
TOPIC_TITLES = [
    ("look", "What the level looks like"),
    ("sense", "Sound, smell and air"),
    ("phenomenon", "What happens there"),
    ("resource", "Food, water and supplies"),
    ("entity", "Entities"),
    ("object", "Objects"),
    ("advice", "Advice to wanderers"),
    ("entrance", "Entrances"),
    ("exit", "Exits"),
    ("difficulty", "Survival difficulty"),
]


def quote_block(text: str) -> str:
    return "\n".join("> " + line for line in text.strip().splitlines())


def write_index(index: dict) -> None:
    lines = [
        "# Lore from The Backrooms wiki",
        "",
        "The mod's lore, entity and descriptions are taken from [The Backrooms wiki on Wikidot](https://backrooms-wiki.wikidot.com/),",
        "so nothing about the world had to be invented. This folder keeps what was taken, word for word, with its source.",
        "",
        f"**Licence.** The wiki's text is licensed {wiki_fetch.LICENCE}. Everything in this folder, and the level text made from it,",
        "stays under that licence: credit the wiki and the page, and share changes under the same terms. Each saved page",
        "names its authors near the top, as the wiki page does.",
        "",
        "## Saved pages",
        "",
        "| Page | Wiki rating | Saved (UTC) | File |",
        "| --- | --- | --- | --- |",
    ]
    for slug in sorted(index, key=lambda s: (not s.startswith("normal"), s)):
        page = index[slug]
        lines.append(f"| [{page['title']}]({page['url']}) | {page.get('rating') or ''} | {page['fetched'][:10]} | [`wiki/{page['file']}`](wiki/{page['file']}) |")
    lines += [
        "",
        "`wiki/index.json` lists the same pages with the links each one has to other wiki pages, which is how to find",
        "the next page worth saving. Save more with `python generator/wiki_fetch.py <page name from the url>`.",
        "",
        "## Lore sheets",
        "",
    ]
    sheets = sorted(path for path in LORE.glob("*.md") if path.name != "README.md")
    for sheet in sheets:
        title = sheet.read_text(encoding="utf-8").splitlines()[0].lstrip("# ")
        lines.append(f"- [{title}]({sheet.name})")
    if not sheets:
        lines.append("None yet.")
    lines += [
        "",
        "A lore sheet is made for each level generated from the wiki (`python generator/lore_doc.py`). It lists the",
        "quoted facts the generator worked from and shows, for every line the players read, which facts it rests on.",
        "",
    ]
    (LORE / "README.md").write_text("\n".join(lines), encoding="utf-8", newline="\n")


def write_sheet(level: dict, index: dict) -> Path | None:
    wiki = level.get("wiki")
    if not isinstance(wiki, dict):
        return None
    facts_path = wiki_fetch.WIKI_DIR / f"{wiki['level']}.facts.json"
    all_facts = json.loads(facts_path.read_text(encoding="utf-8"))["facts"] if facts_path.is_file() else wiki.get("facts", [])
    cited = {fact["id"] for fact in wiki.get("facts", [])}
    pages = wiki.get("pages", {})
    page_title = pages.get(wiki["level"], {}).get("title", wiki["level"])
    lines = [
        f"# {page_title}: lore sheet",
        "",
        f"Source pages: " + ", ".join(f"[{page['title']}]({page['url']})" for page in pages.values()) + ".",
        f"Text quoted from The Backrooms wiki, {wiki.get('licence', wiki_fetch.LICENCE)}. Full saved pages are in [`wiki/`](wiki/).",
        "",
        "## On the wiki",
        "",
        f"- **Survival difficulty:** class {wiki.get('difficulty', {}).get('class', '?')}: "
        + " ".join(wiki.get("difficulty", {}).get("lines", [])),
        f"- **Entity in the map:** {level['monsters'][0]['name']} ([{pages.get(wiki['entity'], {}).get('title', wiki['entity'])}]"
        f"({pages.get(wiki['entity'], {}).get('url', '')})), played by the game's own Skin Stealer.",
        f"- **Main exit:** {wiki.get('exitTo', '?')}.",
        "",
        "## Quoted facts",
        "",
        f"{len(all_facts)} facts were taken from the pages; each quote is word for word. "
        f"The {len(cited)} marked **used** are cited by something in the map.",
        "",
    ]
    for topic, title in TOPIC_TITLES:
        group = [fact for fact in all_facts if fact["topic"] == topic]
        if not group:
            continue
        lines += [f"### {title}", ""]
        for fact in group:
            url = pages.get(fact["page"], index.get(fact["page"], {})).get("url", "")
            used = " **used**" if fact["id"] in cited else ""
            lines += [f"**{fact['id']}**{used}. {fact['claim']} ([{fact['page']}]({url}))", "", quote_block(fact["quote"]), ""]
    lines += [
        "## The mod's own rules",
        "",
        "Where the map follows the game or the mod instead of the wiki, a line cites one of these rules.",
        "",
    ]
    for rule_id, rule in wiki.get("mechanics", {}).items():
        lines.append(f"- **{rule_id}.** {rule}")
    lines += ["", "## What the players read, and what it rests on", "", f"Written by OpenAI ({wiki.get('model', '?')}) on {wiki.get('generated', '?')[:10]}.", ""]
    because = wiki.get("because", {})

    def cites(place: str) -> str:
        return ", ".join(because.get(place, [])) or "none"

    lines += ["| Where | Text | Rests on |", "| --- | --- | --- |"]

    def row(where: str, text: str, place: str) -> None:
        lines.append(f"| {where} | {str(text).replace('|', '/').replace(chr(10), ' ')} | {cites(place)} |")

    row("Briefing", level.get("briefing", ""), "briefing")
    for name, theme in level.get("themes", {}).items():
        row(f"Look `{name}`", "props: " + (", ".join(theme.get("props", [])) or "none"), f"themes.{name}")
    for room in level["rooms"]:
        row(f"Room `{room['id']}` ({room['theme']})", room["description"], f"rooms.{room['id']}")
    for key, text in level.get("text", {}).items():
        row(f"Line `{key}`", " / ".join(text) if isinstance(text, list) else text, f"text.{key}")
    lines.append("")
    out = LORE / f"{level['id'].replace('_', '-')}.md"
    out.write_text("\n".join(lines), encoding="utf-8", newline="\n")
    return out


def main() -> int:
    index = json.loads((wiki_fetch.WIKI_DIR / "index.json").read_text(encoding="utf-8"))
    for level_file in sorted((ROOT / "levels").glob("*.json")):
        if level_file.name.endswith((".dod.json", ".editor.json")):
            continue
        out = write_sheet(json.loads(level_file.read_text(encoding="utf-8")), index)
        if out is not None:
            print(f"wrote {out.relative_to(ROOT)}")
    write_index(index)
    print(f"wrote {(LORE / 'README.md').relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
