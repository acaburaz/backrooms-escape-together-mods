"""Settings shared by the generator and the scripts: the .env file and where the game is installed.

Values come from the environment first, then from a `.env` file in the repo root (never committed;
see `.env.example`). Nothing here writes a value anywhere.

    OPENAI_API_KEY   key for the level generators
    OPENAI_MODEL     model for the level generators
    BET_GAME_DIR     folder of the game, e.g. D:\\SteamLibrary\\steamapps\\common\\Backrooms_Escape_Together
                     Only needed when Steam's own library list does not lead to it.
"""
from __future__ import annotations

import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MOD_NAME = "CustomBackroomsMap"
GAME_FOLDER = "Backrooms_Escape_Together"
WIN64 = ("BET", "Binaries", "Win64")


def load_env(path: Path | None = None) -> None:
    """Read KEY=value lines from .env into the environment. What is already set stays as it is."""
    path = path or ROOT / ".env"
    if not path.is_file():
        return
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip().removeprefix("export ").strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        if key and key not in os.environ:
            os.environ[key] = value


def steam_libraries() -> list[Path]:
    """Every Steam library folder on this machine, from Steam's own list."""
    roots: list[Path] = []
    try:
        import winreg

        for hive, key, name in (
            (winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam", "SteamPath"),
            (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Valve\Steam", "InstallPath"),
        ):
            try:
                with winreg.OpenKey(hive, key) as handle:
                    roots.append(Path(winreg.QueryValueEx(handle, name)[0]))
            except OSError:
                pass
    except ImportError:
        pass
    roots += [
        Path(r"C:\Program Files (x86)\Steam"),
        Path.home() / ".steam" / "steam",
        Path.home() / ".local" / "share" / "Steam",
    ]
    libraries: list[Path] = []
    for root in roots:
        listing = root / "steamapps" / "libraryfolders.vdf"
        if root.is_dir() and root not in libraries:
            libraries.append(root)
        if listing.is_file():
            for found in re.findall(r'"path"\s+"([^"]+)"', listing.read_text(encoding="utf-8", errors="replace")):
                library = Path(found.replace("\\\\", "\\"))
                if library.is_dir() and library not in libraries:
                    libraries.append(library)
    return libraries


def game_dir() -> Path:
    """The game's folder. Raises SystemExit with what to do when it cannot be found."""
    load_env()
    named = os.environ.get("BET_GAME_DIR", "").strip()
    if named:
        path = Path(named)
        if path.joinpath(*WIN64).is_dir():
            return path
        raise SystemExit(f"BET_GAME_DIR is {named}, but there is no {'/'.join(WIN64)} folder in it")
    for library in steam_libraries():
        path = library / "steamapps" / "common" / GAME_FOLDER
        if path.joinpath(*WIN64).is_dir():
            return path
    raise SystemExit(
        "Backrooms: Escape Together was not found in any Steam library. "
        "Set BET_GAME_DIR to the game's folder (in the environment or in .env)."
    )


def win64_dir() -> Path:
    return game_dir().joinpath(*WIN64)


def installed_mod_dir() -> Path:
    """Where the mod goes: beside the UE4SS that the game loads."""
    return win64_dir() / "ue4ss" / "Mods" / MOD_NAME
