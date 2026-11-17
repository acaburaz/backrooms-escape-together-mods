"""Pack the mod into a zip that can be unpacked into the game's UE4SS Mods folder.

    python scripts/package.py

Writes dist/CustomBackroomsMap-<version>.zip (version from the VERSION file). The zip holds the
CustomBackroomsMap folder exactly as scripts/install_mod.py would copy it, plus how to install it and
the credits. dist/ is not committed.
"""
from __future__ import annotations

import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import install_mod  # noqa: E402

HOWTO = """CustomBackroomsMap for Backrooms: Escape Together

1. Install the UE4SS build made for this game (see the README of the repository) into
   <game>\\BET\\Binaries\\Win64 so that <game>\\BET\\Binaries\\Win64\\ue4ss\\Mods exists.
2. Unpack the CustomBackroomsMap folder from this zip into <game>\\BET\\Binaries\\Win64\\ue4ss\\Mods.
3. Start the game and start or load a Level 0 journey. The elevator stops early and opens onto the map.

levels\\active.txt names the level that loads. Delete it to get the older floor, Flickering Halls.
Every player in a co-op game needs the same folder.

Lore, names and descriptions of the wiki level are adapted from The Backrooms wiki
(https://backrooms-wiki.wikidot.com/), CC BY-SA 3.0. See NOTICE.md.
"""


def main() -> int:
    if not install_mod.check():
        print("not packed")
        return 1
    version = (ROOT / "VERSION").read_text(encoding="utf-8").strip()
    out = ROOT / "dist" / f"CustomBackroomsMap-{version}.zip"
    out.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in install_mod.files():
            archive.write(path, "CustomBackroomsMap/" + path.relative_to(install_mod.SOURCE).as_posix())
        archive.writestr("INSTALL.txt", HOWTO)
        archive.write(ROOT / "NOTICE.md", "NOTICE.md")
        archive.write(ROOT / "LICENSE", "LICENSE")
    print(f"wrote {out.relative_to(ROOT)} ({out.stat().st_size // 1024} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
