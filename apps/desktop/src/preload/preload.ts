import { contextBridge, ipcRenderer } from "electron";
import type {
  CliStatus,
  CompanionConfig,
  LoginCode,
  OnboardingScreen,
  VaultState,
} from "../shared/types";

/**
 * Option A bridge for the remote vault /ui page.
 * Keep this surface narrow — no shell, tokens, or passphrase APIs.
 */
contextBridge.exposeInMainWorld("agentioCompanion", {
  present: true as const,
  addProfile(service: string): Promise<void> {
    return ipcRenderer.invoke("companion:addProfile", service);
  },
  reauth(service: string, name?: string): Promise<void> {
    return ipcRenderer.invoke("companion:reauth", service, name);
  },
  openTerminal(): Promise<void> {
    return ipcRenderer.invoke("companion:openTerminal");
  },
});

/** Local onboarding chrome only — not injected into remote hub pages. */
contextBridge.exposeInMainWorld("agentioOnboarding", {
  getConfig(): Promise<CompanionConfig> {
    return ipcRenderer.invoke("onboarding:getConfig");
  },
  setVaultUrl(url: string, remember: boolean): Promise<void> {
    return ipcRenderer.invoke("onboarding:setVaultUrl", url, remember);
  },
  cliStatus(): Promise<CliStatus> {
    return ipcRenderer.invoke("onboarding:cliStatus");
  },
  startCliInstall(): Promise<void> {
    return ipcRenderer.invoke("onboarding:startCliInstall");
  },
  continueWithCli(): Promise<void> {
    return ipcRenderer.invoke("onboarding:continueWithCli");
  },
  vaultState(): Promise<VaultState> {
    return ipcRenderer.invoke("onboarding:vaultState");
  },
  startLogin(): Promise<void> {
    return ipcRenderer.invoke("onboarding:startLogin");
  },
  openApproval(): Promise<void> {
    return ipcRenderer.invoke("onboarding:openApproval");
  },
  cancelLogin(): Promise<void> {
    return ipcRenderer.invoke("onboarding:cancelLogin");
  },
  onLoginCode(cb: (code: LoginCode) => void): () => void {
    const handler = (_e: Electron.IpcRendererEvent, code: LoginCode) => cb(code);
    ipcRenderer.on("onboarding:loginCode", handler);
    return () => ipcRenderer.removeListener("onboarding:loginCode", handler);
  },
  createLocalVault(passphrase: string): Promise<void> {
    return ipcRenderer.invoke("onboarding:createLocalVault", passphrase);
  },
  openLocalVault(): Promise<void> {
    return ipcRenderer.invoke("onboarding:openLocalVault");
  },
  openRemoteVault(): Promise<void> {
    return ipcRenderer.invoke("onboarding:openRemoteVault");
  },
  closeVault(): Promise<void> {
    return ipcRenderer.invoke("onboarding:closeVault");
  },
  onCliProgress(
    cb: (payload: { percent: number; label: string }) => void,
  ): () => void {
    const handler = (
      _e: Electron.IpcRendererEvent,
      payload: { percent: number; label: string },
    ) => cb(payload);
    ipcRenderer.on("onboarding:cliProgress", handler);
    return () => ipcRenderer.removeListener("onboarding:cliProgress", handler);
  },
  onNavigate(cb: (screen: OnboardingScreen) => void): () => void {
    const handler = (_e: Electron.IpcRendererEvent, screen: OnboardingScreen) =>
      cb(screen);
    ipcRenderer.on("onboarding:navigate", handler);
    return () => ipcRenderer.removeListener("onboarding:navigate", handler);
  },
});
