/** Narrow companion bridge — Option A (see docs/plans/electron-companion-spec.md). */
export interface AgentioCompanionBridge {
  present: true;
  addProfile(service: string): Promise<void>;
  reauth(service: string, name?: string): Promise<void>;
  openTerminal(): Promise<void>;
}

export type OnboardingScreen = "S1" | "S2" | "S3" | "S4" | "S5" | "S6";

export interface CompanionConfig {
  vaultUrl: string;
  rememberUrl: boolean;
  /** Stubbed CLI version string after fake install. */
  cliVersion: string | null;
}

export const DEFAULT_CONFIG: CompanionConfig = {
  vaultUrl: "",
  rememberUrl: true,
  cliVersion: null,
};

declare global {
  interface Window {
    agentioCompanion?: AgentioCompanionBridge;
    agentioOnboarding?: {
      getConfig(): Promise<CompanionConfig>;
      setVaultUrl(url: string, remember: boolean): Promise<void>;
      startCliInstall(): Promise<void>;
      skipCliUsePath(): Promise<void>;
      unlockStub(passphrase: string): Promise<{ ok: boolean; error?: string }>;
      openVault(): Promise<void>;
      onCliProgress(
        cb: (payload: { percent: number; label: string }) => void,
      ): () => void;
      onNavigate(cb: (screen: OnboardingScreen) => void): () => void;
    };
  }
}

export {};
