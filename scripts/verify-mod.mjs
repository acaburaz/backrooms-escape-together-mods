import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const index = JSON.parse(readFileSync(join(root, "docs", "game-index.json"), "utf8"));
let gameDir;
try {
  gameDir = execFileSync("python", [join(root, "scripts", "gamedir.py")], { encoding: "utf8" }).trim();
} catch (error) {
  console.error(String(error.stderr || error.message).trim());
  process.exit(1);
}
const manifest = readFileSync(join(gameDir, "Manifest_UFSFiles_Win64.txt"), "utf8");
const requiredPaths = [
  ...index.maps,
  ...index.levelDefinitions,
  ...index.server,
  ...index.pickerWidgets,
  ...index.player,
  ...index.entities,
  ...index.items,
  ...index.doors,
];
const missing = requiredPaths.filter((path) => !manifest.includes(path));
if (missing.length) {
  console.error(`manifest is missing ${missing.join(", ")}`);
  process.exit(1);
}

// The mod is two scripts now: main.lua hosts, halls.lua builds and runs the floor.
const scripts = join(root, "mod", "CustomBackroomsMap", "Scripts");
const lua = ["main.lua", "halls.lua"].map((name) => readFileSync(join(scripts, name), "utf8")).join("\n");
const needles = [
  "CBR_MAP_PICKER_V1",
  "BPW_JourneyEntry",
  "WBP_CreateGameOnboarding",
  "W_Lobby",
  "ClientMessage",
  "120",
  "the_yellow_static",
  "BP_SkinStealer",
  "BP_Survivor_Character",
  "BP_Level0Manager",
  "DO NOT LOOK BACK",
  "start_epilogue",
  "update_seal",
  "update_fake",
  "CurrentObjectives",
  "early_objectives",
];
const absent = needles.filter((needle) => !lua.includes(needle));
if (absent.length) {
  console.error(`mod is missing ${absent.join(", ")}`);
  process.exit(1);
}
// Sanity and stamina are the game's. The mod keeps none of its own, and nothing in it sends a player
// back to the first room for running out of them.
const gone = ["G.hunger", "G.stamina", "moveHunger", "hungerStart", "collapse()", "HUNGER"].filter((needle) => lua.includes(needle));
if (gone.length) {
  console.error(`mod still has its own hunger or stamina: ${gone.join(", ")}`);
  process.exit(1);
}
console.log("mod contract passed");
