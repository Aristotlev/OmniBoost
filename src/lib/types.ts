export type Severity = "critical" | "warning" | "info";

export interface Tweak {
  id: string;
  category: string;
  title: string;
  desc: string;
  default: boolean;
  timeout: number;
  reboot?: boolean;
  needs?: "nvidia" | "amd" | "discord";
  warn?: boolean;
  /** Long step the user can stop from the run screen. */
  skippable?: boolean;
  /** verify: re-checked in the fast batch once applied. always: runs every boost. once: skipped while a recent run completed it. */
  repeat: "verify" | "always" | "once";
}

export interface RunStep {
  status: "done" | "skipped" | "failed" | "manual";
  summary: string;
  changes?: number;
  endedAt?: number;
  endedAtLocal?: string;
  elapsedMs?: number;
  via?: "run" | "verify" | "journal";
}

/** What earlier boosts did, saved by the app after every step. */
export interface LastRun {
  synthetic?: boolean;
  version?: string;
  startedAt: number | null;
  finishedAt: number | null;
  planned: string[];
  current: string | null;
  steps: Record<string, RunStep>;
}

export interface Issue {
  severity: Severity;
  area: string;
  title: string;
  detail: string;
  fix?: string;
  open?: string;
}

export interface RamModule {
  slot: string;
  bank: string;
  channel: string | null;
  capacityGB: number;
  speed: number;
  configured: number;
  manufacturer: string;
  part: string;
  type: string;
  ratedFromPart: number | null;
}

export interface Gpu {
  name: string;
  vendor: string;
  driver: string;
  driverDate: string | null;
  driverAgeDays: number | null;
  vramGB: number | null;
}

export interface Disk {
  name: string;
  media: string;
  bus: string;
  sizeGB: number;
  health: string;
  temp: number | null;
  wear: number | null;
}

export interface Display {
  device: string;
  name: string;
  width: number;
  height: number;
  hz: number;
  maxHz: number;
  primary: boolean;
}

export interface Game {
  name: string;
  exe: string;
  source: string;
  playtimeMin: number;
}

export interface Scan {
  os: { name: string; version: string; build: string };
  machine: { name: string; maker: string; model: string; board: string; laptop: boolean };
  cpu: { name: string; cores: number; threads: number; maxMHz: number; x3dDual: boolean };
  gpus: Gpu[];
  ram: { totalGB: number; type: string; modules: RamModule[]; dualChannel: boolean | null };
  disks: Disk[];
  volumes: { letter: string; label: string; sizeGB: number; freeGB: number }[];
  displays: Display[];
  battery: { wearPct: number | null } | null;
  temps: { cpu: number | null; gpu: number | null };
  power: { scheme: string };
  startupCount: number;
  games: Game[];
  issues: Issue[];
  score: number;
  hasBackup: boolean;
  vendors: { nvidia: boolean; amd: boolean };
  apps: { discord: boolean; steam: boolean; chrome: boolean; edge: boolean };
}

export interface MonTick {
  t: number;
  cpuLoad?: number;
  ramUsedGB?: number;
  ramPct?: number;
  cpuTemp?: number;
  gpuTemp?: number;
  gpuLoad?: number;
  gpuClock?: number;
  gpuPower?: number;
  gpuFan?: number;
}

export interface ManualItem {
  title: string;
  detail: string;
  open?: string;
}

export interface StepResult {
  status: "done" | "skipped" | "failed" | "manual";
  summary: string;
  reboot?: boolean;
  freedBytes?: number;
  changes?: number;
  manual?: ManualItem[];
}

export type LineKind = "CHANGE" | "SAME" | "INFO" | "WARN" | "STEP" | "STDERR" | "RESULT";

export type BoostEvent =
  | { type: "start"; id: string; index: number; total: number }
  | { type: "line"; id: string; kind: LineKind; data: Record<string, unknown> }
  | { type: "end"; id: string; result: StepResult; elapsedMs: number }
  | { type: "done"; elapsedMs: number };

export interface FeedItem {
  key: number;
  id: string;
  kind: LineKind;
  target?: string;
  before?: string;
  after?: string;
  value?: string;
  msg?: string;
  path?: string;
}
