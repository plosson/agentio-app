import { spawn, type ChildProcess } from "node:child_process";
import type { LoginCode, VaultState } from "../../shared/types";
import { AgentioError, cliEnv, cliError, run, stripAnsi, type CliLocation } from "./process";

/*
 * The only place that reads the CLI's output. Each function notes what it
 * relies on, as checked against PINNED_CLI_VERSION. When the CLI gains
 * --json (plosson/agentio#87), only this file changes.
 */

const STATUS_TIMEOUT_MS = 30_000;
const VAULT_INIT_TIMEOUT_MS = 30_000;
/** The CLI gives up after its 10-minute code expiry; this only guards a hang. */
const LOGIN_TIMEOUT_MS = 11 * 60_000;

/**
 * Where the app's CLI keeps credentials. Relies on `status --json --no-test`:
 * `hub` and `canManageProfiles` in remote mode, and `VAULT_NOT_CONFIGURED`
 * when there is neither a vault nor a login.
 */
export async function vaultState(loc: CliLocation): Promise<VaultState> {
  const result = await run(loc.binPath, ["status", "--json", "--no-test"], {
    env: cliEnv(loc),
    timeoutMs: STATUS_TIMEOUT_MS,
  });
  if (result.exitCode !== 0) {
    const err = cliError(result.stderr, result.exitCode, "agentio status failed");
    if (err.code === "VAULT_NOT_CONFIGURED") return { mode: "none" };
    throw err;
  }
  let status: { hub?: unknown; canManageProfiles?: unknown };
  try {
    status = JSON.parse(result.stdout);
  } catch {
    throw new AgentioError("agentio status did not print JSON", null, null, 0);
  }
  if (status.hub === undefined) return { mode: "local" };
  if (typeof status.hub !== "string") {
    throw new AgentioError("agentio status reported an unexpected hub", null, null, 0);
  }
  return { mode: "remote", hub: status.hub, canManageProfiles: status.canManageProfiles === true };
}

/** Create a local vault. The passphrase goes through stdin, never argv. */
export async function initVault(loc: CliLocation, passphrase: string): Promise<void> {
  const result = await run(loc.binPath, ["vault", "init", "--passphrase-stdin", "--no-migrate"], {
    env: cliEnv(loc),
    timeoutMs: VAULT_INIT_TIMEOUT_MS,
    input: passphrase,
  });
  if (result.exitCode !== 0) {
    throw cliError(result.stderr, result.exitCode, "Could not create the vault");
  }
}

/** The code `login` prints, "Your code: XXXX-XXXX" (the hub's code alphabet). */
const LOGIN_CODE = /^Your code: ([A-Z0-9]{4}-[A-Z0-9]{4})$/;

/**
 * Sign in to a hub with `agentio login`, which stores a key token in the
 * CLI's home. `onCode` gets the code to approve as soon as it is printed;
 * the approval page is `<hub>/ui#authorize=<code>`, as the CLI builds it.
 * Success is confirmed with `vaultState`, not from the login text.
 */
export async function login(
  loc: CliLocation,
  hubUrl: string,
  opts: { name: string; signal?: AbortSignal; onCode: (code: LoginCode) => void },
): Promise<Extract<VaultState, { mode: "remote" }>> {
  let codeSeen = false;
  const result = await run(loc.binPath, ["login", hubUrl, "--no-browser", "--name", opts.name], {
    env: cliEnv(loc),
    timeoutMs: LOGIN_TIMEOUT_MS,
    signal: opts.signal,
    onLine: (line, stream) => {
      const match = stream === "stderr" ? LOGIN_CODE.exec(line.trim()) : null;
      if (!match || codeSeen) return;
      codeSeen = true;
      opts.onCode({ userCode: match[1], verifyUrl: `${hubUrl}/ui#authorize=${match[1]}` });
    },
  });
  if (opts.signal?.aborted) {
    throw new AgentioError("Sign-in was cancelled", null, null, result.exitCode);
  }
  if (result.exitCode !== 0) {
    throw cliError(result.stderr, result.exitCode, "Sign-in failed");
  }
  const state = await vaultState(loc);
  if (state.mode !== "remote" || state.hub !== hubUrl) {
    throw new AgentioError(
      "agentio finished the sign-in, but does not report this hub",
      null,
      null,
      0,
    );
  }
  return state;
}

/*
 * The local daemon. It always listens on 0.0.0.0:7890 in this CLI version
 * (no option to change it yet, see plosson/agentio#87), so the app checks
 * the port first and talks to it on the loopback address.
 */

export const DAEMON_URL = "http://127.0.0.1:7890";
const HEALTH_TIMEOUT_MS = 2_000;
const DAEMON_START_TIMEOUT_MS = 15_000;
const DAEMON_STOP_TIMEOUT_MS = 5_000;
const HEALTH_POLL_MS = 250;

/** The daemon's `GET /health` (JSON: `{ status, locked }`); null when nothing answers. */
export async function daemonHealth(): Promise<{ locked: boolean } | null> {
  try {
    const res = await fetch(`${DAEMON_URL}/health`, {
      signal: AbortSignal.timeout(HEALTH_TIMEOUT_MS),
    });
    const body = (await res.json()) as { status?: unknown; locked?: unknown };
    return body.status === "ok" ? { locked: body.locked === true } : null;
  } catch {
    return null;
  }
}

export interface DaemonHandle {
  url: string;
  /** Resolves when the daemon exits, for whatever reason. */
  exited: Promise<void>;
  stop(): Promise<void>;
}

/** Start `agentio daemon start` and resolve once `/health` answers. */
export async function startDaemon(loc: CliLocation): Promise<DaemonHandle> {
  if (await daemonHealth()) {
    throw new AgentioError(
      "An agentio daemon is already running on port 7890, probably your own. Stop it, then try again.",
      null,
      null,
      null,
    );
  }
  const child = spawn(loc.binPath, ["daemon", "start"], {
    env: cliEnv(loc),
    stdio: ["ignore", "ignore", "pipe"],
  });
  let stderr = "";
  child.stderr.setEncoding("utf8").on("data", (chunk: string) => (stderr += stripAnsi(chunk)));
  const exited = new Promise<number | null>((resolve) => {
    child.on("error", () => resolve(null));
    child.on("close", (code) => resolve(code));
  });

  const deadline = Date.now() + DAEMON_START_TIMEOUT_MS;
  let early: number | null | undefined;
  void exited.then((code) => (early = code));
  while (Date.now() < deadline) {
    if (early !== undefined) {
      throw cliError(stderr, early, "The agentio daemon stopped while starting");
    }
    if (await daemonHealth()) {
      return { url: DAEMON_URL, exited: exited.then(() => {}), stop: () => stopChild(child, exited) };
    }
    await new Promise((r) => setTimeout(r, HEALTH_POLL_MS));
  }
  await stopChild(child, exited);
  throw new AgentioError("The agentio daemon did not start in time", null, null, null);
}

/** SIGTERM (the daemon shuts down cleanly on it), then SIGKILL if it lingers. */
async function stopChild(child: ChildProcess, exited: Promise<unknown>): Promise<void> {
  if (child.exitCode !== null || child.signalCode !== null) return;
  child.kill("SIGTERM");
  const timer = setTimeout(() => child.kill("SIGKILL"), DAEMON_STOP_TIMEOUT_MS);
  await exited;
  clearTimeout(timer);
}
