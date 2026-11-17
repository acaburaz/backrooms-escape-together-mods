# For agents working in this repository

What this is, how to install and play: `README.md`. This file says where the data is, how a level is made from the wiki, how the Unreal editor round trip works, what "done" means, and which rules bind.

## State on 2026-11-17

- Active level: **Level 1 - "Habitable Zone"** (`levels/level_1_habitable_zone.json`), written by OpenAI (`gpt-5.5`) from 62 quoted wiki facts. It passes all 13 definition-of-done checks and the offline checks.
- **Not yet run in the game:** the wiki level (its looks, props, refuge rule, crate, hall dials, level-driven text) and hand-made layouts. The older level `the_yellow_static` was played in the game before `halls.lua` got these additions.
- **Not yet run in a real Unreal editor:** `unreal/cbr_unreal.py`. It passes against `scripts/fake_unreal.py`, which was written from Epic's Python API reference.
- Only wiki page `level-1` has been through the generator.

## Where the data is

| What | Where |
| --- | --- |
| Saved wiki pages (plain text; url, rating, fetch time, licence in the header) | `docs/lore/wiki/<slug>.md` |
| Index of saved pages and the links each one has | `docs/lore/wiki/index.json` |
| The list the level was picked from | `docs/lore/wiki/normal-levels-i.md` |
| Pages the level uses | `docs/lore/wiki/level-1.md`, `entity-10.md`, `object-1.md` |
| Pages saved for reference | `docs/lore/wiki/level-0.md`, `level-2.md`, `level-3.md`, `level-4.md` |
| Quoted facts from those pages (`id`, `page`, `topic`, `claim`, `quote`) | `docs/lore/wiki/level-1.facts.json` |
| Readable lore: index and one sheet per wiki level | `docs/lore/README.md`, `docs/lore/level-1-habitable-zone.md` (made by `generator/lore_doc.py`) |
| The level with every citation (`wiki.facts`, `wiki.because`, `wiki.mechanics`) | `levels/level_1_habitable_zone.json` |
| Result of the last definition-of-done run | `levels/level_1_habitable_zone.dod.json` |
| What the game loads (the level without the citations) | `mod/CustomBackroomsMap/levels/level_1_habitable_zone.lua` |
| Which level the mod loads | `mod/CustomBackroomsMap/levels/active.txt` (one file name; without it, `the_yellow_static.lua`) |
| Every line of text the mod takes from a level file, with its limits | `generator/text_keys.json` |
| Rules of the mod that the text must not contradict (M1 to M15) | `MECHANICS` in `generator/wiki_level.py` |
| Everything the mod builds for a level, piece by piece | `unreal/layouts/<level>.layout.json` (made by `scripts/dump_layout.py`) |
| Handwork from the Unreal editor | `levels/<level>.editor.json` and `mod/CustomBackroomsMap/levels/<level>.editor.lua` (none yet) |
| Game asset names the mod refers to | `docs/game-index.json` |
| Settings: `.env` loading and finding the game folder | `generator/settings.py` |

To read a level with its citations: `python scripts/show_level.py levels/level_1_habitable_zone.json --facts`.

Fetch more pages with `python generator/wiki_fetch.py <slug> [<slug> ...]` (`--refresh` to fetch again), then `python generator/lore_doc.py`. The slug is the last part of the page url. Pages are served without a login; the text is in `div#page-content`.

## Why Level 1

Picked from [Normal Levels I](https://backrooms-wiki.wikidot.com/normal-levels-i) because the page already describes what the mod does:

- The game's monster is a Skin Stealer. [Entity 10](https://backrooms-wiki.wikidot.com/entity-10) gives its habitat as "Most commonly Level 1, Level 2, and Level 3", and Level 1's entity table lists it.
- Level 1 has "Flickering": the lights go out and entities hunt. That is the mod's lights-out hunt.
- During Flickering the page tells wanderers to get into a corridor section. The mod turns that into refuges.
- Crates with food and Almond Water ([Object 1](https://backrooms-wiki.wikidot.com/object-1)) appear on the level. Almond Water is an item in the game.
- You arrive from Level 0, which is where the game's elevator is. The main exit is Level 2, reached by walking on while pipes and dials appear. The mod's exit is a long hall.

## Make or remake a level

```bash
python generator/wiki_level.py --level level-1 --entity entity-10 --object almond_water=object-1 --activate
python generator/lore_doc.py          # lore sheet for docs/lore
python scripts/dump_layout.py         # layout for the Unreal editor
python scripts/offline_check.py
python scripts/install_mod.py
```

- Needs `OPENAI_API_KEY` in the environment or in `.env` (ignored by git; `node scripts/verify-no-secret.mjs` checks that nothing publishable holds a key). `OPENAI_MODEL` picks the model (default `gpt-5.5`).
- `--refresh` fetches the pages again and extracts the facts again. Without it the saved pages and facts are reused and only the design is redone (about two minutes).
- `--seed` changes the layout (rooms, locks, where items lie). The layout and its solution come from `generator/generate_level.py`; OpenAI does not get to move anything.
- `--activate` writes `active.txt`.
- The `.lua` file is written only when every check passes. Each run gives different wording.

How it works:

1. `wiki_fetch.py` saves the pages.
2. OpenAI extracts facts. Each must carry a word-for-word quote; quotes that are not on the page are dropped by code, and a second call drops claims that say more than their quote.
3. OpenAI gets the facts, the mod's rules (M1 to M15), the fixed layout and `text_keys.json`, and returns the title, looks, room descriptions, every line of text, and for each of them the ids of the facts and rules it rests on.
4. `wiki_dod.py` checks the result. Failures go back to OpenAI, up to `--rounds` times.

## Definition of done

The wiki has no page that defines "done" for a mod. A wiki level page has fixed parts: survival difficulty, description, entities, bases and communities, entrances and exits. Done here means the map carries each part that a sixteen-room floor can carry, in the wiki's words, plus being playable. `python generator/wiki_dod.py levels/<id>.json` must print `wiki definition of done passed`.

| Check | Part of the wiki page | What must hold |
| --- | --- | --- |
| W1 | licence | Every page used is saved with url and licence; the level carries a credit line |
| W2 | all | Every fact the level cites is a word-for-word quote from a saved page |
| W3 | title | The level has the wiki's name and number |
| W4 | Survival difficulty | Class and its lines recorded as on the page |
| W5 | Description | At least three looks and every room cite facts about how the level looks, sounds or smells |
| W6 | Entities | The entity is named as its page names it, and the level page lists it |
| W7 | Description (resources) | Food and drink cite facts; Almond Water is named as its object page names it |
| W8 | Entrances and exits | The opening cites an entrance fact; the last sign names the level a cited exit fact names |
| W9 | all | Every key in `text_keys.json` is present, within length, keeps its placeholders and instructions, and cites a fact, a rule, or both |
| W10 | all | No level, entity or object number and no name that is on none of the saved pages; no flashlight advice |
| P1 | playable | A route from the elevator to the exit exists and needs both food and rest; the refuge rule is on |
| P2 | playable | Rooms only describe what the mod builds there; nothing calls the map safe; the exit sign is not EXIT |
| P3 | playable | The lines `halls.lua` reads are exactly the keys in `text_keys.json` |

What the checks do not judge: whether a cited fact really fits its line. They check that the citation exists, is quoted on the page and is of the right topic. Read the lore sheet after each run. In the current level one citation is loose: the `refuge` line cites the advice about overconfidence (F54) rather than the advice to get into a corridor section (F21).

The second half of done is that the mod runs with the level:

- `python scripts/offline_check.py` plays every level file through `halls.lua` against mocked engine objects (`scripts/offline_mock.lua`, `offline_scenario.lua`): build, hand-made layout if there is one, opening lines, every room, a hunt, a refuge, the hall, the last room, loop 2, and the installed `main.lua` loading the active level. Needs `pip install lupa`. It finds mistakes in the mod's Lua and in level files. It says nothing about what the real engine does.
- A run in the game. **Still to do** for the wiki level.

## Where the map departs from the wiki

Say these plainly when asked; do not paper over them.

- The wiki rates Level 1 class 1, "Safe and Secure". The map is not safe: the Skin-Stealer kills during Flickering (rule M14). The class is recorded in the level file but the text never calls the place safe.
- Bases, outposts and communities (M.E.G. Base Alpha and others) are not in the map.
- The sign at the end reads LEVEL 2, as the wiki's exit does, but the door leads back to the same floor as the next loop. The game has no Level 2.
- The wiki's refuge during Flickering is a corridor section. In the map it is a room with a bed, marked by a green lamp that stays lit.
- The wiki's Flickering cannot be predicted. The map's comes every two to three minutes and each time a part is taken.
- Arrival is by the game's Level 0 elevator stopping early, not by noclipping.
- Controls hints ("F9 rests and tries the door") and the tape, valve, fuse and key puzzle are the mod's own and cite rules, not the wiki.

## What a level file can switch on in the mod

In `mod/CustomBackroomsMap/Scripts/halls.lua`. A level that sets none of these plays like `the_yellow_static.lua`.

- `level.text`: every subtitle, sign, HUD word and objective row (`L("key", "old wording")`).
- `level.themes`: colours, lamp and `props` per look. Props: `pillar`, `column`, `crates`, `shelf`, `pipes`, `puddle`, `growth`, `debris` (the `DECOR` table; the same list with descriptions is `PROPS` in `generator/wiki_dod.py`, keep the two in step).
- `rules.refuge`: rooms with a bed are refuges. While every player stands in one during a hunt the mod started, the Skin-Stealer is not led to them and the level is not told it is dark. A hunt started by the game's own blackout is not affected. Whether this stops a Skin-Stealer that is already chasing has not been seen in the game.
- `rules.creeper = "crate"`: the thing that creeps closer is a crate instead of a chair.
- `rules.exitPipes`: more pipes and wall dials the further into the exit hall.
- `level.editor` (from `<level>.editor.lua`, attached by `main.lua`): handwork from the Unreal editor. `pieces`, `lights`, `texts` are added; generated pieces whose key is in `remove` are hidden.

## Unreal editor round trip

Steps for a person: `docs/unreal-editor.md`. For an agent:

- `scripts/dump_layout.py` runs `halls.lua` with `H.build(origin, { record = true })` against the mock and writes every shape, lamp and sign to `unreal/layouts/<level>.layout.json`. Run it after any change to a level or to how `halls.lua` builds; `--check` and `test_unreal_roundtrip.py` (U1) fail when a saved layout is out of date.
- A piece's key is `kind|x|y|z|sx|sy|sz` in whole units: `piece_key` in `halls.lua` and `key_of` in `unreal/cbr_layout.py` must stay the same.
- `unreal/cbr_unreal.py` is the only file that imports `unreal`. Keep logic out of it: comparing and checking is in `cbr_layout.py`, which is tested.
- `generator/editor_layout.py` checks an export and writes the `.editor.lua`. It refuses an export whose removed keys are not in the current layout.
- `python scripts/test_unreal_roundtrip.py` covers all of this except the real editor.

## Rules that still bind

- **Never commit `.env` or any key.** `.gitignore` covers it; run `node scripts/verify-no-secret.mjs` before every push.
- Wiki text is CC BY-SA 3.0. Keep the credit line in the level file (the mod writes it to `UE4SS.log` when the floor is built), the headers on saved pages, and `NOTICE.md`.
- Do not hand-edit generated wording in the level files; change the rules, the contract or the checks and regenerate, so every line keeps a citation.
- Nothing extracted from the game goes into the repo: no meshes, textures, sounds. No travel or cheat commands to enter the map.
- No machine paths in scripts. The game folder comes from `generator/settings.py` (Steam's library list, or `BET_GAME_DIR`).
- In UE4SS Lua, never call `:GetFName()` on an object without checking `:IsValid()` first. On a null object it crashes the game and `pcall` does not catch it.
- Shell heredocs eat backslashes. Write scripts that contain `\n` or `\b` with a file-writing tool, not through a heredoc.
- Ignored by git and safe to ignore: `dev/` (probes and one-off patch scripts), `shots/`, `vendor/`, `export/`, `dist/`.
