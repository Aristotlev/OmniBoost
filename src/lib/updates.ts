// In-app updates through the Tauri updater (signed releases on GitHub).
import { isTauri } from "./api";

export type PendingUpdate = {
  version: string;
  install: (onProgress: (pct: number) => void) => Promise<void>;
};

export async function appVersion(): Promise<string> {
  if (!isTauri) return "1.0.2";
  const { getVersion } = await import("@tauri-apps/api/app");
  return getVersion();
}

export async function checkForUpdate(): Promise<PendingUpdate | null> {
  if (!isTauri) return null;
  const { check } = await import("@tauri-apps/plugin-updater");
  const update = await check();
  if (!update) return null;
  return {
    version: update.version,
    install: async (onProgress) => {
      let total = 0;
      let done = 0;
      await update.downloadAndInstall((ev) => {
        if (ev.event === "Started") total = ev.data.contentLength ?? 0;
        if (ev.event === "Progress") {
          done += ev.data.chunkLength;
          if (total) onProgress(Math.round((done / total) * 100));
        }
        if (ev.event === "Finished") onProgress(100);
      });
      // Windows closes the app to run the installer, which reopens it. This covers the rest.
      const { relaunch } = await import("@tauri-apps/plugin-process");
      await relaunch();
    },
  };
}
