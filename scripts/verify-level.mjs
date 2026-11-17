import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));

function fail(message) {
  console.error(message);
  process.exit(1);
}

function runPython() {
  const args = [
    "generator/generate_level.py",
    "--seed",
    "1360",
    "--out",
    "levels/.verify-level.json",
    "--lua",
    "levels/.verify-level.lua",
  ];
  for (const command of ["python", "py"]) {
    const result = spawnSync(command, args, { cwd: root, encoding: "utf8" });
    if (result.error && result.error.code === "ENOENT") continue;
    if (result.status !== 0) {
      fail(result.stderr || result.stdout || "generator failed");
    }
    return;
  }
  fail("python was not found");
}

function adjacency(level) {
  const graph = new Map(level.rooms.map((room) => [room.id, []]));
  for (const link of level.links) {
    graph.get(link.a).push([link.b, link.lock]);
    graph.get(link.b).push([link.a, link.lock]);
  }
  return graph;
}

function indexes(level) {
  const keys = [];
  const notes = [];
  for (const contents of Object.values(level.contents)) {
    for (const item of contents.keys) keys.push(item.id);
    for (const item of contents.puzzle) notes.push(item.id);
  }
  const index = (ids) => Object.fromEntries([...ids].sort().map((id, i) => [id, i]));
  return { keys: index(keys), notes: index(notes) };
}

function applyEnter(level, room, keys, notes, idx) {
  const taken = [];
  for (const item of level.contents[room].keys) {
    const bit = 1 << idx.keys[item.id];
    if ((keys & bit) === 0) {
      keys |= bit;
      taken.push(item.id);
    }
  }
  for (const item of level.contents[room].puzzle) {
    const bit = 1 << idx.notes[item.id];
    if ((notes & bit) === 0) {
      notes |= bit;
      taken.push(item.id);
    }
  }
  return { keys, notes, taken };
}

// The mod has no hunger or tiredness of its own, so a route only has to respect the locked doors.
function solve(level) {
  const graph = adjacency(level);
  const idx = indexes(level);
  let required = 0;
  for (const puzzleId of level.exit.requires) {
    if (!(puzzleId in idx.notes)) return null;
    required |= 1 << idx.notes[puzzleId];
  }
  const startBits = applyEnter(level, level.start, 0, 0, idx);
  const start = [level.start, startBits.keys, startBits.notes];
  const keyOf = (state) => state.join("|");
  const queue = [start];
  const seen = new Set([keyOf(start)]);
  while (queue.length > 0) {
    const state = queue.shift();
    const [room, keys, notes] = state;
    if (room === level.exit.room && (notes & required) === required) return state;
    for (const [other, lock] of graph.get(room)) {
      if (lock && (!(lock in idx.keys) || (keys & (1 << idx.keys[lock])) === 0)) continue;
      const entered = applyEnter(level, other, keys, notes, idx);
      const next = [other, entered.keys, entered.notes];
      if (!seen.has(keyOf(next))) {
        seen.add(keyOf(next));
        queue.push(next);
      }
    }
  }
  return null;
}

function replay(level) {
  const graph = adjacency(level);
  const idx = indexes(level);
  let required = 0;
  for (const puzzleId of level.exit.requires) required |= 1 << idx.notes[puzzleId];
  let room = level.start;
  let bits = applyEnter(level, room, 0, 0, idx);
  let keys = bits.keys;
  let notes = bits.notes;
  const owned = new Set(bits.taken);
  const steps = level.solution.steps;
  if (!steps.length || steps[steps.length - 1].action !== "exit") return "solution does not exit";
  for (const step of steps) {
    if (step.action === "move") {
      const link = graph.get(room).find(([other]) => other === step.to);
      if (!link) return `no door from ${room} to ${step.to}`;
      if (link[1] && (keys & (1 << idx.keys[link[1]])) === 0) return `locked door ${link[1]}`;
      room = step.to;
      bits = applyEnter(level, room, keys, notes, idx);
      keys = bits.keys;
      notes = bits.notes;
      for (const id of bits.taken) owned.add(id);
    } else if (step.action === "take") {
      if (!owned.has(step.id)) return `took ${step.id} before reaching it`;
    } else if (step.action === "exit") {
      if (room !== level.exit.room || (notes & required) !== required) return "exit is locked";
    } else {
      return `unknown action ${step.action}`;
    }
  }
  return null;
}

function assertLevel(level) {
  if (level.rooms.length < 12) fail("expected a multi-room complex");
  if (level.monsters.length < 1 || level.monsters[0].patrol.length < 3) fail("expected a patrolling monster");
  const food = Object.values(level.contents).reduce((sum, contents) => sum + contents.food.length, 0);
  const rest = Object.values(level.contents).reduce((sum, contents) => sum + contents.rest.length, 0);
  if (food < 3 || rest < 2) fail("expected food and beds");
  if (level.exit.requires.length < 3) fail("expected a multi-part exit puzzle");
  // Sanity and stamina are the game's. A level that still carries numbers for the mod's old ones is stale.
  for (const name of ["hungerStart", "staminaStart", "moveHunger", "moveStamina"]) {
    if (name in level.rules) fail(`level still has rules.${name}`);
  }
  for (const contents of Object.values(level.contents)) {
    for (const item of [...contents.food, ...contents.rest]) {
      if ("hunger" in item || "stamina" in item || "callsMonster" in item) fail(`${item.id} still carries hunger or stamina numbers`);
    }
  }
  if (level.briefing.includes("r0_0") || level.briefing.includes(level.start)) fail("briefing reveals a room id");
  const patrol = level.monsters[0].patrol;
  const graph = adjacency(level);
  for (let i = 1; i < patrol.length; i += 1) {
    if (!graph.get(patrol[i - 1]).some(([other]) => other === patrol[i])) fail("monster patrol is disconnected");
  }
  const broken = structuredClone(level);
  for (const contents of Object.values(broken.contents)) contents.keys = [];
  if (solve(broken) !== null) fail("negative control solved a level without its key");
  if (solve(level) === null) fail("independent search found no way out");
  const replayError = replay(level);
  if (replayError) fail(replayError);
}

runPython();
const generated = JSON.parse(readFileSync(join(root, "levels", ".verify-level.json"), "utf8"));
assertLevel(generated);
const shippedPath = join(root, "levels", "the_yellow_static.json");
const shipped = JSON.parse(readFileSync(shippedPath, "utf8"));
assertLevel(shipped);
const lua = readFileSync(join(root, "mod", "CustomBackroomsMap", "levels", "the_yellow_static.lua"), "utf8");
if (!lua.startsWith("return {") || !lua.includes(shipped.pickerLabel) || !lua.includes(shipped.title)) {
  fail("lua level does not match the shipped json");
}
console.log("level verification passed");
