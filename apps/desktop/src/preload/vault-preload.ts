import { contextBridge, ipcRenderer } from "electron";

/**
 * Vault BrowserWindow preload — Option A only.
 * Do not expose onboarding APIs to remote hub HTML.
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
