# Lore from The Backrooms wiki

The mod's lore, entity and descriptions are taken from [The Backrooms wiki on Wikidot](https://backrooms-wiki.wikidot.com/),
so nothing about the world had to be invented. This folder keeps what was taken, word for word, with its source.

**Licence.** The wiki's text is licensed CC BY-SA 3.0 (https://creativecommons.org/licenses/by-sa/3.0/). Everything in this folder, and the level text made from it,
stays under that licence: credit the wiki and the page, and share changes under the same terms. Each saved page
names its authors near the top, as the wiki page does.

## Saved pages

| Page | Wiki rating | Saved (UTC) | File |
| --- | --- | --- | --- |
| [Levels List](https://backrooms-wiki.wikidot.com/normal-levels-i) |  | 2026-11-17 | [`wiki/normal-levels-i.md`](wiki/normal-levels-i.md) |
| [Entity 10 - "Skin-Stealer"](https://backrooms-wiki.wikidot.com/entity-10) | +178 | 2026-11-17 | [`wiki/entity-10.md`](wiki/entity-10.md) |
| [Level 0 - "Threshold"](https://backrooms-wiki.wikidot.com/level-0) | +228 | 2026-11-17 | [`wiki/level-0.md`](wiki/level-0.md) |
| [Level 1 - "Habitable Zone"](https://backrooms-wiki.wikidot.com/level-1) | +191 | 2026-11-17 | [`wiki/level-1.md`](wiki/level-1.md) |
| [Level 2 - "Abandoned Utility Halls"](https://backrooms-wiki.wikidot.com/level-2) | +56 | 2026-11-17 | [`wiki/level-2.md`](wiki/level-2.md) |
| [Level 3 - "Electrical Station"](https://backrooms-wiki.wikidot.com/level-3) | +63 | 2026-11-17 | [`wiki/level-3.md`](wiki/level-3.md) |
| [Level 4 - "Abandoned Office"](https://backrooms-wiki.wikidot.com/level-4) | +207 | 2026-11-17 | [`wiki/level-4.md`](wiki/level-4.md) |
| [Object 1 - "Almond Water"](https://backrooms-wiki.wikidot.com/object-1) | +126 | 2026-11-17 | [`wiki/object-1.md`](wiki/object-1.md) |

`wiki/index.json` lists the same pages with the links each one has to other wiki pages, which is how to find
the next page worth saving. Save more with `python generator/wiki_fetch.py <page name from the url>`.

## Lore sheets

- [Level 1 - "Habitable Zone": lore sheet](level-1-habitable-zone.md)

A lore sheet is made for each level generated from the wiki (`python generator/lore_doc.py`). It lists the
quoted facts the generator worked from and shows, for every line the players read, which facts it rests on.
