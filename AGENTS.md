# For agents working in this repository

What this is, how to install and play: `README.md`. This file says where the data is, how a level is made from the wiki, how the Unreal editor round trip works, what "done" means, and which rules bind.

## State on 2026-11-17

- Active level: **Level 1 - "Habitable Zone"** (`levels/level_1_habitable_zone.json`), written by OpenAI (`gpt-5.5`) from 62 quoted wiki facts. It passes all 13 definition-of-done checks and the offline checks.
- **Run in the game on 0.4.0, alone:** the elevator arrival, six times (see "The elevator" below), and the first steps into the first room. Nothing further into the floor.
- **Not yet run in the game:** the rest of version 0.3.0 (see "Sanity and stamina" below), co-op, and hand-made layouts. The wiki level was entered in the game once for two minutes on 0.2.0 (the floor built and the elevator stopped; `UE4SS.log`), which is when the owner reported being moved and asked for the mod's own hunger and tiredness to go. Its looks, props, refuge rule, crate and hall dials have not been looked at in the game by an agent. The older level `the_yellow_static` was played in the game before `halls.lua` got these additions.
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
| P1 | playable | A route from the elevator to the exit exists; the refuge rule is on, a room has a bed, the game's food is put out; no numbers of the mod's old hunger and stamina are left |
| P2 | playable | Rooms only describe what the mod builds there; nothing calls the map safe; nothing speaks of hunger, resting, sleeping or passing out; the exit sign is not EXIT |
| P3 | playable | The lines `halls.lua` reads are exactly the keys in `text_keys.json` |

What the checks do not judge: whether a cited fact really fits its line. They check that the citation exists, is quoted on the page and is of the right topic. Read the lore sheet after each run. In the current level one citation is loose: the `refuge` line cites the advice about overconfidence (F54) rather than the advice to get into a corridor section (F21).

The second half of done is that the mod runs with the level:

- `python scripts/offline_check.py` plays every level file through `halls.lua` against mocked engine objects (`scripts/offline_mock.lua`, `offline_scenario.lua`): nothing built before the ride is queued (O17), the ride shortened and the floor lined up with the car (O18), the ride itself with the floor waiting until the doors open (O19), the car and the player left alone and the old level switched off collision first (O20), walking out (O21), build, hand-made layout if there is one, opening lines, every room, three more walks through every room without the player being moved (O14), no hunger or stamina of the mod's own (O15), the dead-end passage closing without moving anybody (O16), a hunt, a refuge, the hall, the last room, loop 2, the ways in without the car (O22), a second player's copy of the mod (O23), and the installed `main.lua` loading the active level. The mock's elevator (`M.add_car` in `offline_mock.lua`) moves and opens the way the game's was measured to. Needs `pip install lupa`. It finds mistakes in the mod's Lua and in level files. It says nothing about what the real engine does.
- A run in the game. **Still to do** for the wiki level beyond the arrival.

## Where the map departs from the wiki

Say these plainly when asked; do not paper over them.

- The wiki rates Level 1 class 1, "Safe and Secure". The map is not safe: the Skin-Stealer kills during Flickering (rule M14). The class is recorded in the level file but the text never calls the place safe.
- Bases, outposts and communities (M.E.G. Base Alpha and others) are not in the map.
- The sign at the end reads LEVEL 2, as the wiki's exit does, but the door leads back to the same floor as the next loop. The game has no Level 2.
- The wiki's refuge during Flickering is a corridor section. In the map it is a room with a bed, marked by a green lamp that stays lit.
- The wiki's Flickering cannot be predicted. The map's comes every two to three minutes and each time a part is taken.
- Arrival is by the game's Level 0 elevator, which stops at the floor, not by noclipping.
- Controls hints ("F9 tries the door") and the tape, valve, fuse and key puzzle are the mod's own and cite rules, not the wiki.

## What a level file can switch on in the mod

In `mod/CustomBackroomsMap/Scripts/halls.lua`. A level that sets none of these plays like `the_yellow_static.lua`.

- `level.text`: every subtitle, sign, HUD word and objective row (`L("key", "old wording")`).
- `level.themes`: colours, lamp and `props` per look. Props: `pillar`, `column`, `crates`, `shelf`, `pipes`, `puddle`, `growth`, `debris` (the `DECOR` table; the same list with descriptions is `PROPS` in `generator/wiki_dod.py`, keep the two in step).
- `rules.refuge`: rooms with a bed are refuges. While every player stands in one during a hunt the mod started, the Skin-Stealer is not led to them and the level is not told it is dark. A hunt started by the game's own blackout is not affected. Whether this stops a Skin-Stealer that is already chasing has not been seen in the game.
- `rules.creeper = "crate"`: the thing that creeps closer is a crate instead of a chair.
- `rules.exitPipes`: more pipes and wall dials the further into the exit hall.
- `level.editor` (from `<level>.editor.lua`, attached by `main.lua`): handwork from the Unreal editor. `pieces`, `lights`, `texts` are added; generated pieces whose key is in `remove` are hidden.

## Sanity and stamina are the game's

Since 0.3.0 the mod keeps no hunger or stamina of its own. Asked for by the owner on 2026-11-17: "use the games built in sanity and stamina, so we can use food correctly", and no more being moved back to the first room.

- Gone from `halls.lua`: the cost per room, the HUD numbers, the warnings, passing out and waking in the first room, F9 on food and beds, and the guess at when food was eaten. Gone from level files: `rules.hungerStart/staminaStart/moveHunger/moveStamina`, the numbers on food and beds, and the lines `wake`, `collapse`, `hungry`, `tired`, `eat`, `restQuiet`, `restLoud`. `python generator/update_level.py levels/<id>.json` takes these out of an older level without changing its wording.
- Food and drink are the game's pickups (`GAME_ITEMS` in `halls.lua`). The mod places them and then leaves them alone. Where the game item cannot be placed, no stand-in is built.
- Beds are furniture. On a level with `rules.refuge` a room with a bed is a refuge; nothing is done on the bed itself.
- The mod moves a player in four places only: each stretch of the long hall (that is how the hall stays long), arriving in the last room, starting the next loop, and being put back after falling out of the floor. Since 0.4.0 the players walk out of the elevator themselves; putting them in the first room at the start is only the last resort when the car does not come (see "The elevator"). The dead-end passage used to carry the player back into the room; now it closes like the first room's doorway does, behind the player's back (`update_fake`). Do not add a trick that moves the player.
- What is known about the game's side comes from names in the game's executable, not from watching it: a `BETSanityComponent` on the survivor (`SanityComponent`), attributes `Sanity`, `MaxSanity`, `SanityDepletionRate`, `Stamina`, `MaxStamina`, `StaminaRegenRate`, the tags `Survivor.Attribute.Sanity.PauseDepletion`, `Survivor.Downed.Sanity`, `Survivor.Death.Sanity`, `Ontology.Item.Consumable.Sanity` and `Ontology.Item.Consumable.Stamina`, and `GetStamina()` / `GetMaxStamina()` on the pawn. So sanity very likely drains over time and items give it back. **Not checked in the game:** how fast sanity drains on this floor, whether the lights-out hunt changes it, and which item gives what. The mod reads and writes none of it. If a refuge should ever pause the drain, the `PauseDepletion` tag is where to look, and it needs a run in the game first.

## The elevator

Since 0.4.0 the game's own elevator brings the players to the floor. Asked for by the owner on 2026-11-17: "Fix the Elevator animation actually stopping on our floor and opening the doors, copy from the real level". Before that the mod cut the ride after three seconds, hid the car and put the players in the first room.

How it works (`H.enter`, `update_arrival`, `build_car_side` in `halls.lua`; `watch_elevator` in `main.lua`):

- `main.lua` asks `H.enter({})` every 200 ms from the start of Level 0. It returns false until the game has queued the ride (`CurrentElevatorMoveData.MoveDuration > 0`), about half a second in.
- Then the mod writes one number, `MoveDistance = -2400` (`CAR.drop`), into `car.ElevatorMovement.CurrentElevatorMoveData`, and builds the floor where the car will stop: floor top 12 above the car's stop height, the first room's west wall 4 in front of the car's origin, a doorway 150 wide and 236 high centred on the car's doors.
- From there it only watches (`G.arrival.state`: `riding`, `stopped`, `open`, `done`). The game brakes the car, calls its own `StartMatch`, and opens the doors. The first opening line is said when the car stops; the floor's clocks, the hunt timer and the rest of the opening start when the doors begin to open. Until then the tick runs only the objectives, the menu cover and the HUD.
- The mod never moves a player, never hides the car or its panel, never switches the car's tick or collision off, and never calls the elevator's own functions.
- Fallbacks, all ending with the players put in the first room behind shut steel landing doors (`shut_car_doorway`): no car or no queued ride after 3 s of movement or 25 s (`cut = true` from `main.lua`), a first room with a room to its west or the dead-end room as first room (`car_side_free`), a car still moving after 75 s, doors still shut 25 s after the stop (`give_up_on_car`).
- Loop 2 and later are built without the car ride, so the landing doors are shut there; the car is still behind them.
- Co-op: the host's message is `[CBR] BUILD x y z car`; another player's mod builds at that place and shortens its own copy of the ride. **Not run with a second player.** Whether the host's change of the distance reaches a player without the mod is not known.

Measured in the game on 2026-11-17 with `scripts/record_elevator.py` and `scripts/probes/elevator_parts.lua` (real Level 0, mod hands off):

| | |
| --- | --- |
| Actor | `BP_ElevatorFinal_C` (`/Script/BETGame.Level0Elevator`, base `Elevator_Base`) at x 284, y 0, yaw -90; z 24915 at the start, -9 at the end |
| Ride | `ElevatorMovement.CurrentElevatorMoveData`: `MoveDistance -24924`, `MoveDuration 27`, `MoveStartHeight 24915`. Queued by `OnAllPlayersJoined` about 0.5 s in, moving about 1.5 s later. A small rise at the start, a dip of about 7 past the target, then it settles |
| Doors | About 1.5 s after `OnElevatorMoveComplete` the game calls `StartMatch` and `MoveElevatorDoors`; `CurrentDoorAlpha` goes 0 to 1 in 4.5 s. The car then stays, doors open |
| Player | Not attached. Stands on the car floor, 109.2 above the car's origin with a capsule half height of 95, so the car floor is 12 above the origin. No level sequence plays |
| Car | `ElevatorMesh` spans x -138..287, y -112.5..107.5 in the world with the car at x 284; doors `SM_Lift_01_Door_01..04` in the plane x 267..272; clear doorway y -69.2..61.7 (centre -3.75, 131 wide), 230 high above the car floor |

With the mod (six rides alone, journey on Level 0): the log reads "The elevator was going -24924; it now goes -2400 and stops at z 22515.0", the car settles at 22515.0, the doors start to open about 30 s after the level starts, and holding W walks the player from the car into the first room with no step (the player's height above the floor reads 97.2 in the car and in the room).

Three things learned the hard way:

- Calling `QueueElevatorMovement` on a car that has already arrived crashed the game a moment later. Change the ride the game queues; do not queue one.
- `FindAllOf("StaticMeshComponent")` also returns instanced meshes. Level 0's chunk manager draws its walls with instanced meshes of up to 20000 copies, and `SetWorldScale3D` on one of those while it is solid took 4.5 s (the whole pass froze the game for 6 to 8 s at the start of the ride). With `SetCollisionEnabled(0)` first, the same call takes 1 ms and the whole pass 0.1 s. `hide_step` keeps that order and also spreads the work over the ride, 6 ms a tick. `scripts/probes/hide_cost.lua` measures it.
- Standing still after the doors open, the player died about two minutes later in two runs and the level restarted (the restart rides worked). The first hunt is due 100 to 140 s after the doors open, so this is very likely the Skin Stealer; it was not watched.

## Unreal editor round trip

Steps for a person: `docs/unreal-editor.md`. For an agent:

- `scripts/dump_layout.py` runs `halls.lua` with `H.build(origin, { record = true })` against the mock and writes every shape, lamp and sign to `unreal/layouts/<level>.layout.json`. Run it after any change to a level or to how `halls.lua` builds; `--check` and `test_unreal_roundtrip.py` (U1) fail when a saved layout is out of date.
- A piece's key is `kind|x|y|z|sx|sy|sz` in whole units: `piece_key` in `halls.lua` and `key_of` in `unreal/cbr_layout.py` must stay the same.
- `unreal/cbr_unreal.py` is the only file that imports `unreal`. Keep logic out of it: comparing and checking is in `cbr_layout.py`, which is tested.
- `generator/editor_layout.py` checks an export and writes the `.editor.lua`. It refuses an export whose removed keys are not in the current layout.
- `python scripts/test_unreal_roundtrip.py` covers all of this except the real editor.

## Releases

The download for players is a GitHub release with one file, `CustomBackroomsMap-<version>.zip`, made by `python scripts/package.py` (the mod folder, `INSTALL.txt`, `NOTICE.md`, `LICENSE`). The README links to `releases/latest`. To publish a version, only when the owner asks for it:

```bash
python scripts/offline_check.py && node scripts/verify-no-secret.mjs
python scripts/package.py
git push origin main
gh release create "v$(cat VERSION)" "dist/CustomBackroomsMap-$(cat VERSION).zip" --title "..." --notes-file <notes>
```

Bump `VERSION` first when the mod changed. Say in the notes what was and was not run in the game.

## Rules that still bind

- **Never commit `.env` or any key.** `.gitignore` covers it; run `node scripts/verify-no-secret.mjs` before every push.
- Wiki text is CC BY-SA 3.0. Keep the credit line in the level file (the mod writes it to `UE4SS.log` when the floor is built), the headers on saved pages, and `NOTICE.md`.
- Do not hand-edit generated wording in the level files; change the rules, the contract or the checks and regenerate, so every line keeps a citation.
- Nothing extracted from the game goes into the repo: no meshes, textures, sounds. No travel or cheat commands to enter the map.
- No machine paths in scripts. The game folder comes from `generator/settings.py` (Steam's library list, or `BET_GAME_DIR`).
- In UE4SS Lua, never call `:GetFName()` on an object without checking `:IsValid()` first. On a null object it crashes the game and `pcall` does not catch it.
- Do not hide, stop or move the game's elevator while it brings the players, and do not call its functions (O20 checks this).
- Shell heredocs eat backslashes. Write scripts that contain `\n` or `\b` with a file-writing tool, not through a heredoc.
- Ignored by git and safe to ignore: `dev/` (probes and one-off patch scripts), `shots/`, `vendor/`, `export/`, `dist/`.
