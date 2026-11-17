# Changing a floor by hand in the Unreal editor

The generator decides rooms, doors, locks and where items lie. Everything you can see is then built from the engine's cubes, cylinders and spheres. You can open that build in the Unreal editor, move things, delete things, add your own shapes, lamps and lettering, and the mod will build the floor your way.

**Status:** the mod's side of this and the logic of the editor script are tested without the editor (`python scripts/test_unreal_roundtrip.py`). The script has **not yet been run inside a real Unreal editor**; if a call fails in your engine version, the Output Log names it.

## What you need

- Unreal Engine 5, any version, any project (an empty Blank project is fine). Nothing is cooked and nothing from the game is used.
- Edit > Plugins > **Python Editor Script Plugin** switched on.
- This repository on the same machine, and Python 3.10+ with `pip install lupa` for the steps outside the editor.

## Steps

1. Make sure the saved layout matches the level (only needed after changing a level or `halls.lua`):

   ```bash
   python scripts/dump_layout.py
   ```

   This writes `unreal/layouts/<level>.layout.json`: every piece, lamp and sign the mod builds for that level.

2. In the editor: File > New Level > **Empty Level**. Open Window > Output Log, set the command type to **Cmd**, and run (with your own path):

   ```
   py "C:/path/to/repo/unreal/cbr_unreal.py" import "C:/path/to/repo/unreal/layouts/level_1_habitable_zone.layout.json"
   ```

   The floor appears at the origin. In the Outliner:

   | Folder | What it is |
   | --- | --- |
   | `CBR/Generated` | walls, floors, props, the exit hall. Yours to change. |
   | `CBR/Generated/Ceiling` | ceilings. Hide this folder (eye icon) to look in from above. |
   | `CBR/Generated/Lamps and signs` | the lamps and signs the mod runs itself (flicker, hunts, lying EXIT signs). Shown for reference; changes to them are ignored. |
   | `CBR/Info` | yellow room names and cyan item names. Reference only. |

   An empty level has no light of its own. Use the Unlit view mode, or the imported lamps.

3. Change things:

   - **Move, scale, rotate or delete** any generated piece.
   - **Add a shape:** duplicate a generated piece (Alt-drag), or place a Cube, Cylinder or Sphere from Place Actors > Shapes. Other meshes are left out on export, because the mod can only build these three.
   - **Colour:** each colour is a material instance under `/Game/CBR/Colors`. Assign another one, or duplicate one and change its `Color`. Without the editor's material tools, add an actor tag instead: `cbr.color:0.5,0.2,0.1`.
   - **Walk-through shape:** add the actor tag `cbr.ghost`. **No shadow:** `cbr.noshadow`.
   - **Add a lamp:** duplicate one from `CBR/Generated/Lamps and signs` and move the copy out of that folder; remove its `cbr.fixed` tag. (A freshly placed Point Light uses other brightness units; the export warns about that.) It goes dark with the rest during a hunt. Tag it `cbr.always` to keep it lit.
   - **Add lettering:** place a Text Render actor. Text, size, colour and yaw are kept.
   - Anything you want the export to skip: tag it `cbr.ignore`.

   Units are centimetres. A room is 800 x 800, 320 high. The first room's outer corner is the origin; x runs toward the exit hall.

4. Export, with the same layout file:

   ```
   py "C:/path/to/repo/unreal/cbr_unreal.py" export "C:/path/to/repo/unreal/layouts/level_1_habitable_zone.layout.json"
   ```

   This writes `levels/<level>.editor.json`: the pieces, lamps and texts you added, and the keys of generated pieces you took out. A generated piece you moved or recoloured counts as taken out and added again.

5. Outside the editor:

   ```bash
   python generator/editor_layout.py level_1_habitable_zone   # -> mod/CustomBackroomsMap/levels/<level>.editor.lua
   python scripts/offline_check.py                             # plays the level with your layout, without the game
   python scripts/install_mod.py
   ```

   The log line `Hand-made layout: N pieces, ... taken out` in `UE4SS.log` confirms the game loaded it.

Save the Unreal level if you want to carry on later. The mod never reads the `.umap`; only the export counts.

## What you cannot change this way

- Where rooms, doorways, locks, items, beds and the exit are. That is the generator's (`--seed`), and the solver checks that the result can be finished.
- The lamps and signs the mod animates.
- The monster, the items and the HUD: those are the game's.

If you block a doorway or wall off an item, the level may no longer be finishable. `offline_check.py` does not notice that: it teleports. Walk the floor in the game.

## When the level is made again

Your handwork lives in its own files (`levels/<level>.editor.json` and `<level>.editor.lua`), so making the level's text again keeps it. If the layout itself changes (another `--seed`, or changes to how `halls.lua` builds), pieces you took out may no longer exist. `editor_layout.py` says so and refuses; run `dump_layout.py`, import the new layout into an empty level, redo the changes and export again.

To drop the handwork, delete both editor files and install again.

## How it works

- `halls.lua` gives every generated piece a key from its shape, place and size (`piece_key`). `scripts/dump_layout.py` runs `halls.lua` against a stand-in engine and records every piece with its key.
- `unreal/cbr_unreal.py` tags each imported actor with its key. On export, `unreal/cbr_layout.py` compares what stands in the level with the layout: untouched pieces are skipped, missing or changed ones go on the `remove` list, everything else is new.
- In the game, `main.lua` loads `<level>.editor.lua` beside the level. `halls.lua` hides generated pieces whose key is on the list (they stay as actors, because doors and tricks hold on to their pieces) and builds the added ones.
