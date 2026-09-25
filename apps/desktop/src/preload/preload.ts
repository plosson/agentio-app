import { contextBridge, ipcRenderer } from "electron";
import type { CompanionConfig, OnboardingScreen } from "../shared/types";

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
  startCliInstall(): Promise<void> {
    return ipcRenderer.invoke("onboarding:startCliInstall");
  },
  skipCliUsePath(): Promise<void> {
    return ipcRenderer.invoke("onboarding:skipCliUsePath");
  },
  unlockStub(passphrase: string): Promise<{ ok: boolean; error?: string }> {
    return ipcRenderer.invoke("onboarding:unlockStub", passphrase);
  },
  openVault(): Promise<void> {
    return ipcRenderer.invoke("onboarding:openVault");
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
