// The mod in the game folder is the mod in this repo, file for file.
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const source = join(root, "mod", "CustomBackroomsMap");
let target;
try {
  target = execFileSync("python", [join(root, "scripts", "gamedir.py"), "--mod"], { encoding: "utf8" }).trim();
} catch (error) {
  console.error(String(error.stderr || error.message).trim());
  process.exit(1);
}

const files = ["enabled.txt"];
for (const name of readdirSync(join(source, "Scripts"))) if (name.endsWith(".lua")) files.push(join("Scripts", name));
for (const name of readdirSync(join(source, "levels"))) if (name.endsWith(".lua") || name === "active.txt") files.push(join("levels", name));

const wrong = [];
for (const file of files) {
  const installed = join(target, file);
  if (!existsSync(installed)) wrong.push(`${file} is missing`);
  else if (!readFileSync(installed).equals(readFileSync(join(source, file)))) wrong.push(`${file} differs`);
}
if (!existsSync(join(source, "levels", "active.txt")) && existsSync(join(target, "levels", "active.txt"))) {
  wrong.push("levels/active.txt is installed but not in the repo");
}
if (!readFileSync(join(source, "Scripts", "main.lua"), "utf8").includes("CBR_MAP_PICKER_V1")) wrong.push("main.lua has lost its marker");

if (wrong.length) {
  console.error(`installed mod at ${target} is not this repo's mod: ${wrong.join("; ")}. Run: python scripts/install_mod.py`);
  process.exit(1);
}
console.log("install verification passed");
