"""Run a Lua snippet inside the running game through the mod's test console.

Usage: python scripts/live.py path/to/snippet.lua
       python scripts/live.py -e "out(1 + 1)"

The console only answers while dev\\enabled.flag exists in the installed mod.
"""
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "generator"))
import settings  # noqa: E402

DEV = str(settings.installed_mod_dir() / "dev")


def main() -> int:
    if len(sys.argv) >= 3 and sys.argv[1] == "-e":
        code = sys.argv[2]
    elif len(sys.argv) >= 2:
        with open(sys.argv[1], encoding="utf-8") as handle:
            code = handle.read()
    else:
        print(__doc__)
        return 2
    wait = float(os.environ.get("LIVE_WAIT", "12"))
    os.makedirs(DEV, exist_ok=True)
    stamp = str(time.time_ns())
    out_path = os.path.join(DEV, "live.out")
    if os.path.exists(out_path):
        os.remove(out_path)
    with open(os.path.join(DEV, "live.lua"), "w", encoding="utf-8") as handle:
        handle.write(f"-- id: {stamp}\n{code}\n")
    deadline = time.time() + wait
    while time.time() < deadline:
        if os.path.exists(out_path):
            try:
                with open(out_path, encoding="utf-8", errors="replace") as handle:
                    text = handle.read()
            except OSError:
                text = ""
            if text.startswith(f"id: {stamp}") and text.endswith("\n"):
                print(text[text.index("\n") + 1 :], end="")
                return 0
        time.sleep(0.15)
    print("no answer from the game (is it running with dev\\enabled.flag?)")
    return 1


if __name__ == "__main__":
    sys.exit(main())
