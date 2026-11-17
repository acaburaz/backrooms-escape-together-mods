#!/usr/bin/env python3
"""Fetch pages of the Backrooms wiki (backrooms-wiki.wikidot.com) into docs/lore/wiki/.

Usage: python generator/wiki_fetch.py level-1 entity-10 object-1
       python generator/wiki_fetch.py --refresh level-1

Each page is saved as docs/lore/wiki/<slug>.md: a header (url, title, rating, fetch time, licence)
followed by the text of the page body. docs/lore/wiki/index.json lists what is there.
A page that is already saved is not fetched again unless --refresh is given.

The wiki's text is licensed CC BY-SA 3.0. Anything built from these files has to credit the wiki
and the page, and be shared under the same licence.
"""
from __future__ import annotations

import argparse
import datetime
import html
import json
import re
import sys
import time
import urllib.request
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WIKI_DIR = ROOT / "docs" / "lore" / "wiki"
BASE = "https://backrooms-wiki.wikidot.com/"
LICENCE = "CC BY-SA 3.0 (https://creativecommons.org/licenses/by-sa/3.0/)"
AGENT = "Mozilla/5.0 (backrooms-custom-map research; one page per second)"

BLOCKS = {"p", "div", "li", "tr", "blockquote", "br", "table", "ul", "ol", "h1", "h2", "h3", "h4", "h5", "h6"}
SKIPPED = {"script", "style", "iframe", "noscript"}
# Page furniture: rating box, navigation, licence box, author pop-up, and blocks of theme CSS.
SKIPPED_CLASSES = {"page-rate-widget-box", "footer-wikiwalk-nav", "licensebox", "creditRate", "info-container", "modalbox", "code", "collapsible-block-folded", "collapsible-block-unfolded-link"}


class Body(HTMLParser):
    """Collects the text inside <div id="page-content">."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.depth = 0          # div depth inside page-content, 0 when outside
        self.skip = 0           # depth inside a skipped element
        self.skip_tags: list[str] = []
        self.out: list[str] = []
        self.links: list[tuple[str, str]] = []
        self.href: str | None = None
        self.link_text: list[str] = []

    def handle_starttag(self, tag, attrs):
        attr = dict(attrs)
        if self.depth == 0:
            if tag == "div" and attr.get("id") == "page-content":
                self.depth = 1
            return
        if self.skip:
            if tag == self.skip_tags[-1]:
                self.skip += 1
            return
        classes = attr.get("class") or ""
        if tag in SKIPPED or SKIPPED_CLASSES.intersection(classes.split()):
            if tag not in ("br", "img", "hr", "input"):
                self.skip = 1
                self.skip_tags.append(tag)
            return
        if tag == "div":
            self.depth += 1
        if tag in ("h1", "h2", "h3", "h4", "h5", "h6"):
            self.out.append("\n\n" + "#" * (int(tag[1]) + 1) + " ")
        elif tag == "li":
            self.out.append("\n- ")
        elif tag in ("td", "th"):
            self.out.append(" | ")
        elif tag in BLOCKS:
            self.out.append("\n")
        if tag == "a" and attr.get("href"):
            self.href = attr["href"]
            self.link_text = []

    def handle_endtag(self, tag):
        if self.depth == 0:
            return
        if self.skip:
            if tag == self.skip_tags[-1]:
                self.skip -= 1
                if self.skip == 0:
                    self.skip_tags.pop()
            return
        if tag == "div":
            self.depth -= 1
        if tag == "a" and self.href is not None:
            text = "".join(self.link_text).strip()
            if text and self.href.startswith("/") and not self.href.startswith("/system:"):
                self.links.append((text, self.href.lstrip("/")))
            self.href = None
        if tag in BLOCKS:
            self.out.append("\n")

    def handle_data(self, data):
        if self.depth == 0 or self.skip:
            return
        self.out.append(data)
        if self.href is not None:
            self.link_text.append(data)

    def text(self) -> str:
        text = "".join(self.out).replace("\xa0", " ")
        text = re.sub(r"[ \t]+", " ", text)
        text = re.sub(r" *\n *", "\n", text)
        text = re.sub(r"\n{3,}", "\n\n", text)
        return text.strip()


def fetch(slug: str) -> dict:
    url = BASE + slug
    request = urllib.request.Request(url, headers={"User-Agent": AGENT})
    with urllib.request.urlopen(request, timeout=40) as response:
        raw = response.read().decode("utf-8", errors="replace")
    title = re.search(r"<title>(.*?)</title>", raw, re.S)
    title = html.unescape(title.group(1)).replace(" - The Backrooms", "").strip() if title else slug
    rating = re.search(r'class="number prw54353">([^<]*)<', raw)
    body = Body()
    body.feed(raw)
    links: dict[str, str] = {}
    for text, target in body.links:
        links.setdefault(target.split("#")[0], text)
    return {
        "slug": slug,
        "url": url,
        "title": title,
        "rating": rating.group(1).strip() if rating else None,
        "fetched": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "text": body.text(),
        "links": links,
    }


def save(page: dict) -> Path:
    WIKI_DIR.mkdir(parents=True, exist_ok=True)
    path = WIKI_DIR / (page["slug"] + ".md")
    header = [
        "---",
        f"url: {page['url']}",
        f"title: {json.dumps(page['title'], ensure_ascii=False)}",
        f"rating: {page['rating']}",
        f"fetched: {page['fetched']}",
        f"licence: {LICENCE}",
        "source: The Backrooms wiki on Wikidot. Authors are listed on the page itself (page history / info box).",
        "---",
        "",
    ]
    path.write_text("\n".join(header) + page["text"] + "\n", encoding="utf-8", newline="\n")
    index_path = WIKI_DIR / "index.json"
    index = json.loads(index_path.read_text(encoding="utf-8")) if index_path.exists() else {}
    index[page["slug"]] = {
        "url": page["url"],
        "title": page["title"],
        "rating": page["rating"],
        "fetched": page["fetched"],
        "file": path.name,
        "links": page["links"],
    }
    index_path.write_text(json.dumps(index, indent=2, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    return path


def load(slug: str, refresh: bool = False) -> str:
    """The saved text of a page (header removed), fetching it first when it is not there."""
    path = WIKI_DIR / (slug + ".md")
    if refresh or not path.exists():
        page = fetch(slug)
        if len(page["text"]) < 200:
            raise RuntimeError(f"{slug}: the page body came back almost empty ({len(page['text'])} characters)")
        save(page)
        time.sleep(1.0)
    text = path.read_text(encoding="utf-8")
    return text.split("\n---\n", 1)[1].strip() if text.startswith("---\n") else text


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("slugs", nargs="+", help="page names as in the url, e.g. level-1 entity-10 object-1")
    parser.add_argument("--refresh", action="store_true", help="fetch again even when the page is already saved")
    args = parser.parse_args()
    for slug in args.slugs:
        text = load(slug, args.refresh)
        print(f"{slug}: {len(text)} characters in docs/lore/wiki/{slug}.md")
    return 0


if __name__ == "__main__":
    sys.exit(main())
