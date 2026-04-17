import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..");
const powershellExe = "powershell.exe";
const wrapperScript = path.join(__dirname, "run-tests.ps1");
const gameRoot = process.env.FACTORIO_GAME_ROOT
  ? path.resolve(repoRoot, process.env.FACTORIO_GAME_ROOT)
  : path.join(repoRoot, "factorio-game");
const untilTick = Number.parseInt(process.env.FACTORIO_TEST_TICKS ?? "700", 10);
const timeoutMs = Number.parseInt(process.env.FACTORIO_TEST_TIMEOUT_MS ?? "180000", 10);

function assertPositiveInteger(value, label) {
  if (!Number.isInteger(value) || value <= 0) {
    throw new Error(`${label} must be a positive integer.`);
  }
}

async function main() {
  assertPositiveInteger(untilTick, "FACTORIO_TEST_TICKS");
  assertPositiveInteger(timeoutMs, "FACTORIO_TEST_TIMEOUT_MS");

  await new Promise((resolve, reject) => {
    const child = spawn(
      powershellExe,
      [
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        wrapperScript,
        "-GameRoot",
        gameRoot,
        "-UntilTick",
        String(untilTick),
      ],
      {
        cwd: repoRoot,
        env: process.env,
        stdio: "inherit",
        windowsHide: true,
      },
    );

    const timer = setTimeout(() => {
      child.kill("SIGKILL");
      reject(new Error(`Factorio test wrapper timed out after ${timeoutMs} ms.`));
    }, timeoutMs);

    child.on("error", (error) => {
      clearTimeout(timer);
      reject(error);
    });

    child.on("exit", (code, signal) => {
      clearTimeout(timer);
      if (signal) {
        reject(new Error(`Factorio test wrapper terminated by signal ${signal}.`));
        return;
      }

      if (code !== 0) {
        reject(new Error(`Factorio test wrapper failed with exit code ${code}.`));
        return;
      }

      resolve();
    });
  });
}

main().catch((error) => {
  console.error(error instanceof Error ? error.stack : error);
  process.exitCode = 1;
});
