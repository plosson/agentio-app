import { spawn } from "node:child_process";
import * as path from "node:path";

/**
 * The app runs its own agentio, never the user's: the binary lives in `bin/`
 * and the CLI gets `home/` as HOME, so its ~/.config/agentio is separate too.
 */
export interface CliLocation {
  binDir: string;
  binPath: string;
  homeDir: string;
}

export function cliLocation(root: string): CliLocation {
  const binDir = path.join(root, "bin");
  const file = process.platform === "win32" ? "agentio.exe" : "agentio";
  return { binDir, binPath: path.join(binDir, file), homeDir: path.join(root, "home") };
}

/**
 * This process's environment without the user's AGENTIO_* settings, which
 * would steer the installer (AGENTIO_VERSION, AGENTIO_GITHUB_REPO…) or the
 * CLI (an AGENTIO_TOKEN puts it in remote mode and makes `login` refuse).
 */
export function isolatedEnv(): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = {};
  for (const [name, value] of Object.entries(process.env)) {
    if (!name.startsWith("AGENTIO_") && !FORCED_COLOR.has(name)) env[name] = value;
  }
  // Plain text: colour codes would hide the lines commands.ts looks for.
  return { ...env, NO_COLOR: "1" };
}

/** Set by e.g. the dev launcher; they override NO_COLOR, so drop them. */
const FORCED_COLOR = new Set(["FORCE_COLOR", "CLICOLOR_FORCE"]);

/** Terminal escape sequences (colours, cursor moves), in case any get through. */
const ANSI_ESCAPE = /\x1b\[[0-9;?]*[ -/]*[@-~]/g;

export function stripAnsi(text: string): string {
  return text.replace(ANSI_ESCAPE, "");
}

/** Environment for the app's CLI: isolated, with its own HOME (USERPROFILE on Windows). */
export function cliEnv(loc: CliLocation): NodeJS.ProcessEnv {
  return { ...isolatedEnv(), HOME: loc.homeDir, USERPROFILE: loc.homeDir };
}

/** A failed CLI run, with the CLI's own error code when it printed one. */
export class AgentioError extends Error {
  constructor(
    message: string,
    readonly code: string | null,
    readonly suggestion: string | null,
    readonly exitCode: number | null,
  ) {
    super(message);
    this.name = "AgentioError";
  }
}

/**
 * Turn stderr and the exit code into an AgentioError. The CLI prints
 * `Error [CODE]: message` and optionally `Suggestion: …`; anything else
 * falls back to the last stderr line.
 */
export function cliError(stderr: string, exitCode: number | null, fallback: string): AgentioError {
  const lines = stderr.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
  let code: string | null = null;
  let message: string | null = null;
  let suggestion: string | null = null;
  for (const line of lines) {
    const coded = /^Error \[([A-Z_]+)\]: (.+)$/.exec(line);
    const plain = /^Error: (.+)$/.exec(line);
    const hint = /^Suggestion: (.+)$/.exec(line);
    if (coded) [code, message] = [coded[1], coded[2]];
    else if (plain) [code, message] = [null, plain[1]];
    else if (hint) suggestion = hint[1];
  }
  return new AgentioError(message ?? lines.at(-1) ?? fallback, code, suggestion, exitCode);
}

export interface RunResult {
  exitCode: number | null;
  stdout: string;
  stderr: string;
}

export interface RunOptions {
  env?: NodeJS.ProcessEnv;
  timeoutMs: number;
  signal?: AbortSignal;
  /** Written to stdin, which is then closed; stdin is empty otherwise. */
  input?: string;
  /** Called with each complete stdout/stderr line as it arrives. */
  onLine?: (line: string, stream: "stdout" | "stderr") => void;
}

/**
 * Run a command to completion and collect its output; never rejects on a
 * non-zero exit (callers read `exitCode`), only when it cannot start.
 * A timeout or abort kills it and reports a null exit code.
 */
export function run(file: string, args: string[], opts: RunOptions): Promise<RunResult> {
  return new Promise((resolve, reject) => {
    const child = spawn(file, args, {
      env: opts.env,
      stdio: [opts.input === undefined ? "ignore" : "pipe", "pipe", "pipe"],
      timeout: opts.timeoutMs,
      signal: opts.signal,
    });
    // A child that exits before reading all input closes the pipe (EPIPE);
    // its exit code tells what happened, so ignore the write error.
    child.stdin?.on("error", () => {});
    child.stdin?.end(opts.input);
    const output = { stdout: "", stderr: "" };
    const read = (stream: "stdout" | "stderr") => {
      // Chunks can split a line, so hold the unfinished part.
      // Progress bars redraw with \r, so treat it as a line break too.
      let pending = "";
      const pipe = child[stream];
      if (!pipe) return;
      pipe.setEncoding("utf8").on("data", (raw: string) => {
        // A chunk could end inside an escape sequence; the CLI only colours
        // whole lines, so in practice sequences arrive complete.
        const chunk = stripAnsi(raw);
        output[stream] += chunk;
        const parts = (pending + chunk).split(/[\r\n]/);
        pending = parts.pop() ?? "";
        for (const line of parts) opts.onLine?.(line, stream);
      });
      pipe.on("end", () => {
        if (pending) opts.onLine?.(pending, stream);
      });
    };
    read("stdout");
    read("stderr");
    child.on("error", (err) => {
      // An abort also emits "close"; report it there with the output so far.
      if (err.name !== "AbortError") reject(err);
    });
    child.on("exit", (_code, signal) => {
      // Killed (abort or timeout): a grandchild may still hold the pipes open,
      // which would delay "close" until it exits, so stop reading now.
      if (signal) {
        child.stdout?.destroy();
        child.stderr?.destroy();
      }
    });
    child.on("close", (code) => resolve({ exitCode: code, ...output }));
  });
}
