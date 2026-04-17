import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import luaparse from "luaparse";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..");

const excludedNames = new Set([
  ".git",
  ".github",
  ".npm-cache",
  "factorio-game",
  "node_modules",
]);

async function collectLuaFiles(dirPath, files = []) {
  const entries = await fs.readdir(dirPath, { withFileTypes: true });
  for (const entry of entries) {
    if (excludedNames.has(entry.name)) {
      continue;
    }

    const fullPath = path.join(dirPath, entry.name);
    if (entry.isDirectory()) {
      await collectLuaFiles(fullPath, files);
      continue;
    }

    if (entry.isFile() && entry.name.endsWith(".lua")) {
      files.push(fullPath);
    }
  }

  return files;
}

async function main() {
  const luaFiles = await collectLuaFiles(repoRoot);
  if (luaFiles.length === 0) {
    throw new Error("No Lua files found to validate.");
  }

  for (const filePath of luaFiles) {
    const source = await fs.readFile(filePath, "utf8");
    luaparse.parse(source, {
      comments: false,
      locations: true,
      luaVersion: "5.2",
      scope: false,
    });
  }

  console.log(`Validated ${luaFiles.length} Lua files.`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.stack : error);
  process.exitCode = 1;
});
