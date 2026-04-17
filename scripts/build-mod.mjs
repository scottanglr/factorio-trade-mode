import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..");
const gameRoot = path.resolve(repoRoot, process.env.FACTORIO_GAME_ROOT ?? "factorio-game");
const modsRoot = path.join(gameRoot, "mods");

const excludedNames = new Set([
  ".git",
  ".github",
  ".npm-cache",
  "factorio-game",
  "node_modules",
]);

async function readInfo() {
  const infoPath = path.join(repoRoot, "info.json");
  const raw = await fs.readFile(infoPath, "utf8");
  return JSON.parse(raw);
}

async function ensureCleanDir(dirPath) {
  await fs.rm(dirPath, { recursive: true, force: true });
  await fs.mkdir(dirPath, { recursive: true });
}

async function build() {
  const info = await readInfo();
  const target = path.join(modsRoot, `${info.name}_${info.version}`);

  await fs.mkdir(modsRoot, { recursive: true });
  await ensureCleanDir(target);

  const entries = await fs.readdir(repoRoot, { withFileTypes: true });
  for (const entry of entries) {
    if (excludedNames.has(entry.name)) {
      continue;
    }

    const sourcePath = path.join(repoRoot, entry.name);
    const destinationPath = path.join(target, entry.name);
    await fs.cp(sourcePath, destinationPath, { recursive: true, force: true });
  }

  const modListPath = path.join(modsRoot, "mod-list.json");
  const modList = {
    mods: [
      { name: "base", enabled: true },
      { name: info.name, enabled: true },
    ],
  };
  await fs.writeFile(modListPath, JSON.stringify(modList, null, 2), "utf8");

  console.log(`Built mod to ${target}`);
}

build().catch((error) => {
  console.error(error instanceof Error ? error.stack : error);
  process.exitCode = 1;
});
