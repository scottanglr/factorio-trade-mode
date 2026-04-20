import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import luaparse from "luaparse";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..");
const runtimeApiPath = path.join(repoRoot, "factorio-game", "doc-html", "runtime-api.json");
const prototypeApiPath = path.join(repoRoot, "factorio-game", "doc-html", "prototype-api.json");

const excludedNames = new Set([
  ".git",
  ".github",
  ".npm-cache",
  "factorio-game",
  "node_modules",
]);

function lineNumberForOffset(source, offset) {
  let line = 1;
  for (let index = 0; index < offset && index < source.length; index += 1) {
    if (source[index] === "\n") {
      line += 1;
    }
  }
  return line;
}

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

function getClassMembers(runtimeApi, className) {
  const classDoc = runtimeApi.classes.find((entry) => entry.name === className);
  if (!classDoc) {
    throw new Error(`Class ${className} not found in runtime-api.json.`);
  }

  return new Set([
    ...(classDoc.attributes ?? []).map((entry) => entry.name),
    ...(classDoc.methods ?? []).map((entry) => entry.name),
  ]);
}

function getUtilitySprites(prototypeApi) {
  const utilitySprites = prototypeApi.prototypes.find((entry) => entry.name === "UtilitySprites");
  if (!utilitySprites) {
    throw new Error("UtilitySprites not found in prototype-api.json.");
  }

  return new Set((utilitySprites.properties ?? []).map((entry) => `utility/${entry.name}`));
}

function visit(node, visitor) {
  if (!node || typeof node !== "object") {
    return;
  }

  visitor(node);

  for (const value of Object.values(node)) {
    if (!value) {
      continue;
    }

    if (Array.isArray(value)) {
      for (const child of value) {
        visit(child, visitor);
      }
      continue;
    }

    if (typeof value === "object") {
      visit(value, visitor);
    }
  }
}

function collectStringMatches(source, pattern) {
  const matches = [];
  for (const match of source.matchAll(pattern)) {
    matches.push({
      value: match[1],
      line: lineNumberForOffset(source, match.index ?? 0),
    });
  }
  return matches;
}

function formatIssue(filePath, line, message) {
  return `${path.relative(repoRoot, filePath)}:${line}: ${message}`;
}

async function main() {
  const [runtimeApiRaw, prototypeApiRaw] = await Promise.all([
    fs.readFile(runtimeApiPath, "utf8"),
    fs.readFile(prototypeApiPath, "utf8"),
  ]);
  const runtimeApi = JSON.parse(runtimeApiRaw);
  const prototypeApi = JSON.parse(prototypeApiRaw);

  const globalMemberSets = {
    game: getClassMembers(runtimeApi, "LuaGameScript"),
    helpers: getClassMembers(runtimeApi, "LuaHelpers"),
    prototypes: getClassMembers(runtimeApi, "LuaPrototypes"),
  };
  const validUtilitySprites = getUtilitySprites(prototypeApi);
  const luaFiles = await collectLuaFiles(repoRoot);
  const issues = [];

  for (const filePath of luaFiles) {
    const source = await fs.readFile(filePath, "utf8");
    const ast = luaparse.parse(source, {
      comments: false,
      locations: true,
      ranges: true,
      luaVersion: "5.2",
      scope: false,
    });

    visit(ast, (node) => {
      if (
        node.type === "MemberExpression" &&
        node.indexer === "." &&
        node.base?.type === "Identifier" &&
        node.identifier?.type === "Identifier"
      ) {
        const baseName = node.base.name;
        const memberName = node.identifier.name;
        const allowed = globalMemberSets[baseName];
        if (allowed && !allowed.has(memberName)) {
          issues.push(
            formatIssue(
              filePath,
              node.loc?.start?.line ?? 1,
              `Unknown ${baseName} member "${memberName}" for Factorio 2.0 docs.`,
            ),
          );
        }
      }
    });

    for (const sprite of collectStringMatches(source, /"(utility\/[A-Za-z0-9_-]+)"/g)) {
      if (!validUtilitySprites.has(sprite.value)) {
        issues.push(
          formatIssue(filePath, sprite.line, `Unknown utility sprite "${sprite.value}".`),
        );
      }
    }

    for (const image of collectStringMatches(source, /\[img=(utility\/[A-Za-z0-9_-]+)\]/g)) {
      if (!validUtilitySprites.has(image.value)) {
        issues.push(
          formatIssue(filePath, image.line, `Unknown utility sprite in rich text "${image.value}".`),
        );
      }
    }

    for (const icon of collectStringMatches(source, /"(__base__\/[^"]+)"/g)) {
      const resolvedPath = path.join(repoRoot, icon.value.replace("__base__/", "factorio-game/data/base/"));
      try {
        await fs.access(resolvedPath);
      } catch {
        issues.push(
          formatIssue(filePath, icon.line, `Missing base asset "${icon.value}".`),
        );
      }
    }
  }

  if (issues.length > 0) {
    console.error("Factorio API validation failed:");
    for (const issue of issues) {
      console.error(`- ${issue}`);
    }
    process.exitCode = 1;
    return;
  }

  console.log(`Validated Factorio API usage across ${luaFiles.length} Lua files.`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.stack : error);
  process.exitCode = 1;
});
