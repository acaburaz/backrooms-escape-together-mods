import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
// Set BLENDER to the program if it is not on PATH or in the usual Windows folder.
const usual = "C:\\Program Files\\Blender Foundation\\Blender 5.0\\blender.exe";
const blender = process.env.BLENDER || (existsSync(usual) ? usual : "blender");
const output = join(root, "export", "the_yellow_static.glb");
if (!existsSync(join(root, "levels", "the_yellow_static.json"))) {
  console.error("level json is missing");
  process.exit(1);
}
const result = spawnSync(
  blender,
  [
    "--background",
    "--python",
    "blender/build_level.py",
    "--",
    "levels/the_yellow_static.json",
    "export/the_yellow_static.glb",
  ],
  { cwd: root, encoding: "utf8", timeout: 110000 }
);
const combined = `${result.stdout || ""}\n${result.stderr || ""}`;
if (result.status !== 0 || !combined.includes("blender level export passed")) {
  console.error(combined.slice(-4000));
  process.exit(1);
}
if (!existsSync(output) || statSync(output).size < 1000) {
  console.error("glb export is missing");
  process.exit(1);
}
const magic = readFileSync(output).subarray(0, 4).toString("utf8");
if (magic !== "glTF") {
  console.error(`unexpected glb magic ${magic}`);
  process.exit(1);
}
console.log("blender level export passed");
