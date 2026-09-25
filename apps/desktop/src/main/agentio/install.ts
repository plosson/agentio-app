import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { CliInfo, CliStatus } from "../../shared/types";
import { cliEnv, isolatedEnv, run, type CliLocation } from "./process";

/**
 * The CLI version the app installs. The app reads the CLI's text output
 * (see commands.ts), so it installs the version that output was checked
 * against rather than "latest". Raise it after checking the new output.
 */
export const PINNED_CLI_VERSION = "3.2.2";

/** Official installers, as documented at https://agentio.houlahop.com/#install. */
const INSTALL_SCRIPT_URL =
  process.platform === "win32"
    ? "https://agentio.houlahop.com/install.ps1"
    : "https://agentio.houlahop.com/install";
const INSTALL_TIMEOUT_MS = 5 * 60_000;
const VERSION_TIMEOUT_MS = 5_000;
const ERROR_TAIL_LINES = 5;
/** A redraw of curl's `--progress-bar`: "#####   42.5%", "###", or its "##O#-#" spinner. */
const PROGRESS_BAR = /^[#=O\-\s]*(?:(\d+(?:\.\d+)?)%)?$/;

export type OnProgress = (progress: { label?: string; percent?: number }) => void;

async function downloadInstallScript(dir: string): Promise<string> {
  const res = await fetch(INSTALL_SCRIPT_URL, {
    signal: AbortSignal.timeout(30_000),
  });
  if (!res.ok) {
    throw new Error(`Could not download the installer (HTTP ${res.status})`);
  }
  const file = path.join(dir, path.basename(new URL(INSTALL_SCRIPT_URL).pathname));
  await fs.promises.writeFile(file, await res.text(), { mode: 0o700 });
  return file;
}

/**
 * Install (or replace) the pinned CLI in the app's own bin dir with the
 * official installer. Never touches PATH, shell rc files or other installs.
 */
export async function installCli(loc: CliLocation, onProgress: OnProgress): Promise<CliInfo> {
  await fs.promises.mkdir(loc.binDir, { recursive: true });
  await fs.promises.mkdir(loc.homeDir, { recursive: true, mode: 0o700 });
  const tmpDir = await fs.promises.mkdtemp(path.join(os.tmpdir(), "agentio-install-"));
  try {
    onProgress({ label: `Downloading installer from ${INSTALL_SCRIPT_URL}…` });
    const script = await downloadInstallScript(tmpDir);
    const [file, args] =
      process.platform === "win32"
        ? ["powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script,
            "-InstallDir", loc.binDir, "-Version", PINNED_CLI_VERSION, "-NoModifyPath"]]
        : ["/bin/sh", [script, "--install-dir", loc.binDir,
            "--version", PINNED_CLI_VERSION, "--no-modify-path"]];
    const tail: string[] = [];
    const result = await run(file, args, {
      env: isolatedEnv(),
      timeoutMs: INSTALL_TIMEOUT_MS,
      onLine: (raw) => {
        const line = raw.trim();
        if (!line) return;
        const bar = PROGRESS_BAR.exec(line);
        if (bar) {
          if (bar[1]) onProgress({ percent: Number(bar[1]) });
          return;
        }
        tail.push(line);
        if (tail.length > ERROR_TAIL_LINES) tail.shift();
        onProgress({ label: line });
      },
    });
    if (result.exitCode !== 0) {
      const reason =
        result.exitCode === null ? "was stopped" : `exited with code ${result.exitCode}`;
      const detail = tail.length ? `: ${tail.join(" · ")}` : "";
      throw new Error(`The installer ${reason}${detail}`);
    }
  } finally {
    await fs.promises.rm(tmpDir, { recursive: true, force: true });
  }
  const cli = await detectCli(loc);
  if (!cli) throw new Error("The installer finished, but agentio could not be run");
  return cli;
}

/** The app's CLI (if installed) compared with the pinned version. */
export async function cliStatus(loc: CliLocation): Promise<CliStatus> {
  const cli = await detectCli(loc);
  return {
    cli,
    required: PINNED_CLI_VERSION,
    upToDate: cli !== null && versionOf(cli.version) === PINNED_CLI_VERSION,
  };
}

/** "3.2.2", "v3.2.2" or "agentio 3.2.2" → "3.2.2"; the raw text if no x.y.z. */
function versionOf(text: string): string {
  return /\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?/.exec(text)?.[0] ?? text;
}

/** Read the app's CLI version; null if it is not installed or does not run. */
export async function detectCli(loc: CliLocation): Promise<CliInfo | null> {
  try {
    const result = await run(loc.binPath, ["--version"], {
      env: cliEnv(loc),
      timeoutMs: VERSION_TIMEOUT_MS,
    });
    const version = result.stdout.trim();
    return result.exitCode === 0 && version ? { path: loc.binPath, version } : null;
  } catch {
    return null;
  }
}
