import type { BoostEvent, LastRun, MonTick, Scan, Tweak } from "./types";
import tweaksJson from "../../src-tauri/scripts/tweaks.json";
import * as mock from "./mock";

export const isTauri = typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;
export const TWEAKS = tweaksJson as Tweak[];

type Unlisten = () => void;

async function core() {
  return import("@tauri-apps/api/core");
}
async function events() {
  return import("@tauri-apps/api/event");
}

export async function scanSystem(onStep: (msg: string) => void): Promise<Scan> {
  if (!isTauri) return mock.scan(onStep);
  const { listen } = await events();
  const un = await listen<{ msg: string }>("scan://step", (e) => onStep(e.payload.msg));
  try {
    const { invoke } = await core();
    return await invoke<Scan>("scan");
  } finally {
    un();
  }
}

export async function onMonitor(cb: (t: MonTick) => void): Promise<Unlisten> {
  if (!isTauri) return mock.monitor(cb);
  const { listen } = await events();
  const un = await listen<MonTick>("monitor://tick", (e) => cb(e.payload));
  const { invoke } = await core();
  await invoke("start_monitor");
  return un;
}

export async function onBoostEvent(cb: (e: BoostEvent) => void): Promise<Unlisten> {
  if (!isTauri) return mock.onBoost(cb);
  const { listen } = await events();
  return listen<BoostEvent>("boost://event", (e) => cb(e.payload));
}

export async function runBoost(ids: string[], verify: string[], options: { restorePoint: boolean; closeApps: boolean }) {
  if (!isTauri) return mock.runBoost(ids, verify, options);
  const { invoke } = await core();
  return invoke("run_boost", { ids, verify, options });
}

export async function skipStep() {
  if (!isTauri) return mock.skip();
  const { invoke } = await core();
  return invoke("skip_step");
}

export async function lastRun(): Promise<LastRun | null> {
  if (!isTauri) return mock.lastRun();
  const { invoke } = await core();
  return invoke<LastRun | null>("last_run");
}

/** End time of a recorded step in ms, or null. */
export function stepTime(s?: { endedAt?: number; endedAtLocal?: string }): number | null {
  if (!s) return null;
  if (s.endedAt) return s.endedAt;
  if (s.endedAtLocal) {
    const t = new Date(s.endedAtLocal).getTime();
    return Number.isNaN(t) ? null : t;
  }
  return null;
}

export function timeAgo(ms: number | null): string {
  if (!ms) return "earlier";
  const m = Math.round((Date.now() - ms) / 60000);
  if (m < 1) return "just now";
  if (m < 60) return `${m} min ago`;
  const h = Math.round(m / 60);
  if (h < 24) return `${h} h ago`;
  const d = Math.round(h / 24);
  return `${d} day${d === 1 ? "" : "s"} ago`;
}

export async function revertAll() {
  if (!isTauri) return mock.revert();
  const { invoke } = await core();
  return invoke("revert_all");
}

export async function backupCount(): Promise<number> {
  if (!isTauri) return mock.backupCount();
  const { invoke } = await core();
  return invoke<number>("backup_count");
}

export async function openTarget(target: string) {
  if (!target) return;
  if (!isTauri) {
    if (/^https?:/.test(target)) window.open(target, "_blank");
    return;
  }
  const { invoke } = await core();
  return invoke("open_target", { target });
}

export async function restartPc() {
  if (!isTauri) return;
  const { invoke } = await core();
  return invoke("restart_pc");
}

export async function windowAction(action: "minimize" | "maximize" | "close") {
  if (!isTauri) return;
  const { getCurrentWindow } = await import("@tauri-apps/api/window");
  const w = getCurrentWindow();
  if (action === "minimize") return w.minimize();
  if (action === "maximize") return w.toggleMaximize();
  return w.close();
}

export function formatBytes(b: number): string {
  if (!b || b < 0) return "0 MB";
  if (b >= 1024 ** 3) return `${(b / 1024 ** 3).toFixed(2)} GB`;
  if (b >= 1024 ** 2) return `${Math.round(b / 1024 ** 2)} MB`;
  return `${Math.round(b / 1024)} KB`;
}

export function formatDuration(ms: number): string {
  const s = Math.max(0, Math.round(ms / 1000));
  if (s < 60) return `${s}s`;
  return `${Math.floor(s / 60)}m ${String(s % 60).padStart(2, "0")}s`;
}
