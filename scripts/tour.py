"""Drive the player through the generated floor with the mod's test console.

Each argument is one step, run in order:
  room:r1_0        walk to the middle of a room
  at:965,165       walk to a point (map units, origin at the corner of the first room)
  item:granola     walk up to an item and face it
  use              press the use key (same call as F9)
  look:90,-10      set view yaw, pitch
  wait:2.5         wait seconds
  god:on / god:off test godmode
  hall:3           walk the exit hall until it has looped 3 times
  shot:name        save the screen to shots/name.png (the game must be in front)
  state            print the state line

Needs the game running with dev\\enabled.flag in the installed mod folder.
"""
import math
import subprocess
import sys
import time
from pathlib import Path

LIVE = str(Path(__file__).with_name("live.py"))

STATE = r"""
local g = CBR.H.state()
if not g then out("STATE none") return end
local have = {} for k, v in pairs(g.have) do if v then have[#have+1] = k end end table.sort(have)
local used = {} for _, it in ipairs(g.items) do if it.taken then used[#used+1] = it.id end end
local errs = 0 for _ in pairs(g.errs) do errs = errs + 1 end
out(string.format("STATE %.0f %.0f %.0f room=%s zone=%s hunger=%d stamina=%d have=%s used=%s exit=%s passes=%d white=%s epi=%s loop=%d seal=%s fake=%s chair=%s god=%s errs=%d sub=%s",
  g.px, g.py, g.pz, tostring(g.roomId), g.zone, g.hunger, g.stamina, table.concat(have, ","), table.concat(used, ","),
  g.exit.state, g.hall.passes, tostring(g.hall.white), g.epi.state, g.loop, g.seal.state, g.fake.state,
  tostring(g.chair and g.chair.moved), tostring(g.god), errs, tostring(g.sub and g.sub.text)))
for k in pairs(g.errs) do out("ERR " .. k) end
"""


def lua(code: str) -> list[str]:
    result = subprocess.run([sys.executable, LIVE, "-e", code], capture_output=True, text=True)
    return [line for line in result.stdout.splitlines() if line.strip()]


def state() -> dict:
    for line in lua(STATE):
        if line.startswith("STATE "):
            parts = line.split(" ")
            info = {"x": float(parts[1]), "y": float(parts[2]), "z": float(parts[3]), "line": line}
            return info
        if line.startswith("ERR"):
            print(line)
    return {"x": 0.0, "y": 0.0, "z": 0.0, "line": "STATE unknown"}


def walk(x: float, y: float, timeout: float = 25.0, near: float = 60.0) -> bool:
    began = time.time()
    last_order = 0.0
    while time.time() - began < timeout:
        if time.time() - last_order > 2.5:
            here = state()
            yaw = math.degrees(math.atan2(y - here["y"], x - here["x"]))
            lua(f"CBR.H.look({yaw:.1f}, -4) CBR.H.walk({x}, {y})")
            last_order = time.time()
        here = state()
        if math.hypot(here["x"] - x, here["y"] - y) < near:
            return True
        time.sleep(0.25)
    print(f"WALK FAILED to {x},{y}; stopped at {here['x']:.0f},{here['y']:.0f}")
    return False


def main() -> int:
    for step in sys.argv[1:]:
        name, _, arg = step.partition(":")
        if name == "room":
            out = lua(f'local x, y = CBR.H.room_center("{arg}") out(x, y)')
            x, y = [float(v) for v in out[-1].split("\t")]
            ok = walk(x, y)
            print(f"room {arg}: {'reached' if ok else 'NOT reached'}")
        elif name == "at":
            x, y = [float(v) for v in arg.split(",")]
            ok = walk(x, y)
            print(f"at {arg}: {'reached' if ok else 'NOT reached'}")
        elif name == "item":
            out = lua(
                f'for _, it in ipairs(CBR.H.state().items) do if it.id == "{arg}" then '
                f'local cx, cy = CBR.H.room_center(it.room) out(it.lx, it.ly, cx, cy) end end'
            )
            ix, iy, cx, cy = [float(v) for v in out[-1].split("\t")]
            length = math.hypot(cx - ix, cy - iy)
            tx, ty = ix + (cx - ix) / length * 200, iy + (cy - iy) / length * 200
            ok = walk(tx, ty, timeout=12, near=85)
            yaw = math.degrees(math.atan2(iy - ty, ix - tx))
            lua(f"CBR.H.look({yaw:.1f}, -24)")
            print(f"item {arg}: {'reached' if ok else 'NOT reached'}")
        elif name == "hall":
            # walk east down the exit hall until it has looped this many times
            want = int(arg)
            began = time.time()
            passes = -1
            while time.time() - began < 90:
                line = state()["line"]
                passes = int(line.split("passes=")[1].split(" ")[0])
                if passes >= want or "white=true" in line:
                    break
                lua("CBR.H.look(0, -2) CBR.H.walk(5750, 2800)")
                time.sleep(1.0)
            print(f"hall passes {passes}")
        elif name == "shot":
            # Only ever capture the game: skip the shot when any other window is in front.
            import ctypes
            from PIL import ImageGrab
            user32 = ctypes.windll.user32
            title = ctypes.create_unicode_buffer(256)
            user32.GetWindowTextW(user32.GetForegroundWindow(), title, 256)
            if not title.value.startswith("Backrooms"):
                print(f"shot {arg}: SKIPPED, the game is not the front window")
            else:
                folder = Path(__file__).resolve().parent.parent / "shots"
                folder.mkdir(exist_ok=True)
                ImageGrab.grab().save(folder / f"{arg}.png")
                print(f"shot {arg}: {state()['line']}")
        elif name == "use":
            lua("if not CBR.H.take() then CBR.H.use() end")
            print("use")
        elif name == "look":
            yaw, pitch = [float(v) for v in arg.split(",")]
            lua(f"CBR.H.look({yaw}, {pitch})")
        elif name == "wait":
            time.sleep(float(arg))
        elif name == "god":
            lua(f"CBR.H.god({'true' if arg == 'on' else 'false'})")
        elif name == "state":
            pass
        else:
            print(f"unknown step {step}")
            return 2
    print(state()["line"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
