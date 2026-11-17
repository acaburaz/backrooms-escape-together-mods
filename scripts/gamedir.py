"""Print where the game is installed. Used by the other scripts so no path is written into them.

    python scripts/gamedir.py           the game's folder
    python scripts/gamedir.py --win64   BET/Binaries/Win64 inside it
    python scripts/gamedir.py --mod     the installed mod folder (ue4ss/Mods/CustomBackroomsMap)

The folder is found through Steam's library list. Set BET_GAME_DIR (environment or .env) to name it yourself.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "generator"))
import settings  # noqa: E402


def main() -> int:
    if "--win64" in sys.argv:
        path = settings.win64_dir()
    elif "--mod" in sys.argv:
        path = settings.installed_mod_dir()
    else:
        path = settings.game_dir()
    print(str(path).replace("\\", "/"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
