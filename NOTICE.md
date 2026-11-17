# Credits and licences

## Code

The mod's Lua, the generators and the scripts are under the MIT licence (`LICENSE`).

## Lore: The Backrooms wiki

Lore, names and descriptions are taken or adapted from [The Backrooms wiki on Wikidot](https://backrooms-wiki.wikidot.com/), whose text is licensed [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/). That licence, not MIT, covers:

- `docs/lore/**`: saved wiki pages, quoted facts and lore sheets. Each saved page starts with its url and names its authors as the wiki page does.
- The wiki-derived text in `levels/level_1_habitable_zone.json` and `mod/CustomBackroomsMap/levels/level_1_habitable_zone.lua` (title, briefing, room descriptions, on-screen lines), adapted from:
  - [Level 1 - "Habitable Zone"](https://backrooms-wiki.wikidot.com/level-1)
  - [Entity 10 - "Skin-Stealer"](https://backrooms-wiki.wikidot.com/entity-10)
  - [Object 1 - "Almond Water"](https://backrooms-wiki.wikidot.com/object-1)

The adaptation was written by an OpenAI model from word-for-word quotes of those pages; `docs/lore/level-1-habitable-zone.md` shows which quote each line rests on. If you share or change this text, credit the wiki and the pages and keep it under CC BY-SA 3.0.

## The game

Backrooms: Escape Together belongs to its developers and publisher. This is an unofficial mod. Nothing from the game is included here: no meshes, textures, sounds or code. The map is built at runtime from the engine's basic shapes; the monster and the items you pick up are the game's own, spawned from your installed copy. `docs/game-index.json` only lists names of game assets the mod refers to.

## UE4SS

The mod runs on [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) (MIT). It is not included; install the build made for this game.
