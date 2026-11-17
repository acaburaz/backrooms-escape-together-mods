// Nothing that git would publish holds a key, and .env stays out of git.
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const secrets = [
  /sk-[a-zA-Z0-9_-]{20,}/, // OpenAI
  /gh[pousr]_[A-Za-z0-9]{30,}/, // GitHub
  /AKIA[0-9A-Z]{16}/, // AWS
  /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
];
const skip = new Set(["export", ".unlazy", "node_modules", ".git", "vendor", "dist", "__pycache__"]);

function walk(directory, files) {
  for (const name of readdirSync(directory)) {
    if (skip.has(name) || name === ".env") continue;
    const path = join(directory, name);
    if (statSync(path).isDirectory()) walk(path, files);
    else files.push(path);
  }
}

// In a git repo: every file git tracks or would add. Otherwise: every file except the skipped folders.
let files = [];
const inGit = existsSync(join(root, ".git"));
if (inGit) {
  const listed = execFileSync("git", ["ls-files", "-co", "--exclude-standard", "-z"], { cwd: root, encoding: "utf8" });
  files = listed.split("\0").filter(Boolean).map((name) => join(root, name)).filter((path) => existsSync(path));
} else {
  walk(root, files);
}

const hits = [];
for (const path of files) {
  if (statSync(path).size > 5_000_000) continue;
  const text = readFileSync(path, "latin1");
  if (secrets.some((pattern) => pattern.test(text))) hits.push(relative(root, path));
}
if (hits.length) {
  console.error(`secret found in ${hits.join(", ")}`);
  process.exit(1);
}

if (inGit) {
  const published = files.map((path) => relative(root, path).replaceAll("\\", "/"));
  const env = published.filter((name) => /(^|\/)\.env($|\.)/.test(name) && !name.endsWith(".env.example"));
  if (env.length) {
    console.error(`git would publish ${env.join(", ")}. Add it to .gitignore.`);
    process.exit(1);
  }
  try {
    execFileSync("git", ["check-ignore", "-q", ".env"], { cwd: root });
  } catch {
    console.error(".env is not ignored by git. Add it to .gitignore.");
    process.exit(1);
  }
}

for (const name of ["generate_level.py", "wiki_level.py"]) {
  const generator = readFileSync(join(root, "generator", name), "utf8");
  if (!generator.includes('os.environ.get("OPENAI_API_KEY"')) {
    console.error(`${name} does not read OPENAI_API_KEY from the environment`);
    process.exit(1);
  }
}
console.log(`secret scan passed (${files.length} files${inGit ? " that git would publish" : ""})`);
