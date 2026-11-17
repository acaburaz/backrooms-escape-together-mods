"""Record what the game's own Level 0 elevator does, so the mod can copy it.

    python scripts/record_elevator.py on     arm the recorder, then start the game and start Level 0
    python scripts/record_elevator.py mod    the same, but the mod takes the ride to its own floor
    python scripts/record_elevator.py off    disarm it and switch the test console off again
    python scripts/record_elevator.py log    print the recording

With "on" the mod does not build its floor: the ride runs as the game made it, down to the real
Level 0. With "mod" the mod sends the car to its own floor as usual. Either way
scripts/probes/elevator_record.lua writes what the elevator, its doors, the camera and the player do
to dev/elevator.log in the installed mod folder. Arm it before the game starts; the test console runs
it once when the game comes up.
"""
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "generator"))
import settings  # noqa: E402

PROBE = Path(__file__).with_name("probes") / "elevator_record.lua"


def main() -> int:
    what = sys.argv[1] if len(sys.argv) > 1 else ""
    dev = settings.installed_mod_dir() / "dev"
    log = dev / "elevator.log"
    if what in ("on", "mod"):
        dev.mkdir(parents=True, exist_ok=True)
        code = PROBE.read_text(encoding="utf-8").replace("__LOG__", log.as_posix())
        code = code.replace("__HANDS_OFF__", "true" if what == "on" else "false")
        (dev / "live.out").unlink(missing_ok=True)
        (dev / "live.lua").write_text(f"-- id: {time.time_ns()}\n{code}\n", encoding="utf-8", newline="\n")
        (dev / "enabled.flag").write_text("on\n", encoding="utf-8")
        print(f"armed. Start the game, then start Level 0 and stay in the elevator until its doors have opened.\nrecording goes to {log}")
        return 0
    if what == "off":
        for name in ("enabled.flag", "live.lua", "live.out"):
            (dev / name).unlink(missing_ok=True)
        print("disarmed; the test console is off")
        return 0
    if what == "log":
        if not log.exists():
            print(f"no recording at {log}")
            return 1
        print(log.read_text(encoding="utf-8", errors="replace"))
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
