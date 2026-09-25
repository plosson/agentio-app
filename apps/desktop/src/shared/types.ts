/** Narrow companion bridge — Option A (see docs/plans/electron-companion-spec.md). */
export interface AgentioCompanionBridge {
  present: true;
  addProfile(service: string): Promise<void>;
  reauth(service: string, name?: string): Promise<void>;
  openTerminal(): Promise<void>;
}

/**
 * S1–S3: the app's CLI. "mode": local or remote vault. Remote: S4 (hub URL)
 * then "login" (get a code) and "approving" (the hub's approval page shows).
 * Local: "local" (create the vault if needed). S6: the hub's page shows.
 */
export type OnboardingScreen =
  | "S1" | "S2" | "S3" | "mode" | "S4" | "login" | "approving" | "local" | "S6";

/**
 * While a hub page shows ("approving", S6), the app's page is reduced to a
 * bar this tall at the top of the window and the hub page fills the rest.
 */
export const VAULT_BAR_HEIGHT = 48;

/** A login code to approve on the hub, and the page to approve it on. */
export interface LoginCode {
  userCode: string;
  verifyUrl: string;
}

export interface CliInfo {
  path: string;
  version: string;
}

export interface CliStatus {
  /** The app's own CLI, or null when it is not installed or does not run. */
  cli: CliInfo | null;
  /** The version the app installs and was checked against. */
  required: string;
  /** True when the installed CLI is exactly the required version. */
  upToDate: boolean;
}

/** Where the app's CLI keeps credentials. */
export type VaultState =
  | { mode: "none" }
  | { mode: "local" }
  | { mode: "remote"; hub: string; canManageProfiles: boolean };

export interface CompanionConfig {
  vaultUrl: string;
  rememberUrl: boolean;
  /** Version reported by the app's CLI (`agentio --version`). */
  cliVersion: string | null;
  /** Absolute path of the app's CLI; null until it is installed and checked. */
  cliPath: string | null;
}

export const DEFAULT_CONFIG: CompanionConfig = {
  vaultUrl: "",
  rememberUrl: true,
  cliVersion: null,
  cliPath: null,
};

declare global {
  interface Window {
    agentioCompanion?: AgentioCompanionBridge;
    agentioOnboarding?: {
      getConfig(): Promise<CompanionConfig>;
      setVaultUrl(url: string, remember: boolean): Promise<void>;
      cliStatus(): Promise<CliStatus>;
      startCliInstall(): Promise<void>;
      continueWithCli(): Promise<void>;
      vaultState(): Promise<VaultState>;
      startLogin(): Promise<void>;
      openApproval(): Promise<void>;
      cancelLogin(): Promise<void>;
      onLoginCode(cb: (code: LoginCode) => void): () => void;
      createLocalVault(passphrase: string): Promise<void>;
      openLocalVault(): Promise<void>;
      openRemoteVault(): Promise<void>;
      closeVault(): Promise<void>;
      onCliProgress(
        cb: (payload: { percent: number; label: string }) => void,
      ): () => void;
      onNavigate(cb: (screen: OnboardingScreen) => void): () => void;
    };
  }
}

export {};
