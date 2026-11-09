// Browser preview data. Used only when the UI runs outside the Tauri shell.
import type { BoostEvent, LastRun, LineKind, MonTick, Scan } from "./types";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
let boostListeners: ((e: BoostEvent) => void)[] = [];
let backups = 0;
let skipRequested = false;
const fresh = typeof location !== "undefined" && location.search.includes("fresh");
// Sample record: the last boost stopped during Windows Disk Cleanup, like a closed app or a restart would leave it.
const T0 = Date.now() - 1000 * 60 * 52;
const doneIds = ["restore-point", "clean-temp", "clean-browser", "ram-standby", "pagefile", "power-plan", "power-throttling", "game-mode", "mmcss", "game-priority", "hags", "nvidia-profile", "gpu-driver", "display-refresh", "display-vrr", "visual-effects", "transparency", "startup-apps", "background-apps", "overlays", "notifications", "discord-hwaccel", "browser-background", "net-tcp", "net-nagle", "net-adapter", "disk-scan", "disk-optimize", "drivers-oem"];
let record: LastRun | null = fresh ? null : {
  version: "1.0.1", startedAt: T0, finishedAt: null,
  planned: [...doneIds, "clean-disk", "clean-update"], current: "clean-disk",
  steps: Object.fromEntries(doneIds.map((id, i) => [id, { status: id === "gpu-driver" ? "manual" : "done", summary: "Done", endedAt: T0 + i * 40000, via: "run" }])) as LastRun["steps"],
};

export async function scan(onStep: (m: string) => void): Promise<Scan> {
  for (const s of ["Reading system", "Reading graphics", "Reading temperatures", "Checking memory", "Checking drives", "Reading displays", "Looking for hardware errors", "Finding games"]) {
    onStep(s);
    await sleep(260);
  }
  return {
    os: { name: "Microsoft Windows 11 Pro", version: "10.0.26200", build: "26200" },
    machine: { name: "ARIS-RIG", maker: "Micro-Star International", model: "MS-7E26", board: "MSI MAG B650 TOMAHAWK WIFI", laptop: false },
    cpu: { name: "AMD Ryzen 7 9800X3D 8-Core Processor", cores: 8, threads: 16, maxMHz: 4700, x3dDual: false },
    gpus: [{ name: "NVIDIA GeForce RTX 5080", vendor: "NVIDIA", driver: "576.88", driverDate: "2026-04-14", driverAgeDays: 207, vramGB: 16 }],
    ram: {
      totalGB: 32, type: "DDR5", dualChannel: true,
      modules: [
        { slot: "DIMM 1", bank: "P0 CHANNEL A", channel: "A", capacityGB: 16, speed: 4800, configured: 4800, manufacturer: "G Skill Intl", part: "F5-6000J3038F16G", type: "DDR5", ratedFromPart: 6000 },
        { slot: "DIMM 1", bank: "P0 CHANNEL B", channel: "B", capacityGB: 16, speed: 4800, configured: 4800, manufacturer: "G Skill Intl", part: "F5-6000J3038F16G", type: "DDR5", ratedFromPart: 6000 },
      ],
    },
    disks: [
      { name: "Samsung SSD 990 PRO 2TB", media: "SSD", bus: "NVMe", sizeGB: 1863, health: "Healthy", temp: 41, wear: 3 },
      { name: "ST2000DM008-2FR102", media: "HDD", bus: "SATA", sizeGB: 1863, health: "Healthy", temp: 34, wear: null },
    ],
    volumes: [{ letter: "C", label: "", sizeGB: 1862, freeGB: 412.4 }, { letter: "D", label: "Games", sizeGB: 1863, freeGB: 120.7 }],
    displays: [
      { device: "\\\\.\\DISPLAY1", name: "ASUS VG27AQ3A", width: 2560, height: 1440, hz: 60, maxHz: 180, primary: true },
      { device: "\\\\.\\DISPLAY2", name: "DELL P2422H", width: 1920, height: 1080, hz: 60, maxHz: 60, primary: false },
    ],
    battery: null,
    temps: { cpu: 46.1, gpu: 38 },
    power: { scheme: "Balanced" },
    startupCount: 14,
    games: [
      { name: "Counter-Strike 2", exe: "D:\\SteamLibrary\\steamapps\\common\\Counter-Strike Global Offensive\\game\\bin\\win64\\cs2.exe", source: "Steam", playtimeMin: 48210 },
      { name: "Lineage II", exe: "C:\\NCSOFT\\Lineage II\\system\\l2.exe", source: "Steam", playtimeMin: 23130 },
      { name: "VALORANT", exe: "C:\\Riot Games\\VALORANT\\live\\ShooterGame\\Binaries\\Win64\\VALORANT-Win64-Shipping.exe", source: "Riot", playtimeMin: 0 },
      { name: "Fortnite", exe: "C:\\Program Files\\Epic Games\\Fortnite\\FortniteGame\\Binaries\\Win64\\FortniteClient-Win64-Shipping.exe", source: "Epic", playtimeMin: 0 },
      { name: "Elden Ring", exe: "D:\\SteamLibrary\\steamapps\\common\\ELDEN RING\\Game\\eldenring.exe", source: "Steam", playtimeMin: 9120 },
    ],
    issues: [
      { severity: "critical", area: "Memory", title: "RAM is running below its rated speed", detail: "Memory runs at 4800 MT/s but is rated for 6000 MT/s. Enable XMP (Intel) or EXPO (AMD) in the BIOS. Windows apps cannot change this." },
      { severity: "warning", area: "Display", title: "Monitor running at 60 Hz", detail: "ASUS VG27AQ3A supports 180 Hz at this resolution. Boost switches it." },
      { severity: "warning", area: "Drivers", title: "NVIDIA driver is 207 days old", detail: "NVIDIA GeForce RTX 5080 runs driver 576.88. New drivers add game-specific performance fixes.", fix: "Update GPU driver", open: "https://www.nvidia.com/en-us/drivers/" },
      { severity: "info", area: "Power", title: "Power plan: Balanced", detail: "The CPU is allowed to downclock and park cores. Boost switches to a max performance plan." },
      { severity: "info", area: "Windows", title: "Xbox Game Bar recording is on", detail: "Background capture costs FPS. Boost turns it off." },
      { severity: "info", area: "Graphics", title: "Hardware-accelerated GPU scheduling is off", detail: "Lowers CPU overhead and is required for DLSS Frame Generation." },
    ],
    score: 58,
    hasBackup: backups > 0,
    vendors: { nvidia: true, amd: false },
    apps: { discord: true, steam: true, chrome: true, edge: true },
  };
}

export async function monitor(cb: (t: MonTick) => void) {
  let i = 0;
  const id = setInterval(() => {
    i++;
    const w = Math.sin(i / 4);
    cb({
      t: Date.now(),
      cpuLoad: Math.round(14 + 9 * w + Math.random() * 6),
      ramUsedGB: +(11.2 + 0.4 * w).toFixed(1),
      ramPct: Math.round(35 + w),
      cpuTemp: +(46 + 3 * w + Math.random()).toFixed(1),
      gpuTemp: Math.round(38 + 2 * w),
      gpuLoad: Math.round(6 + 5 * Math.abs(w)),
      gpuClock: Math.round(420 + 300 * Math.abs(w)),
      gpuPower: Math.round(28 + 8 * Math.abs(w)),
      gpuFan: 0,
    });
  }, 1000);
  return () => clearInterval(id);
}

export async function onBoost(cb: (e: BoostEvent) => void) {
  boostListeners.push(cb);
  return () => {
    boostListeners = boostListeners.filter((x) => x !== cb);
  };
}
const emit = (e: BoostEvent) => boostListeners.forEach((l) => l(e));

type L = [LineKind, Record<string, unknown>];
const C = (target: string, before: string, after: string, path = ""): L => ["CHANGE", { target, before, after, path }];
const S = (target: string, value: string): L => ["SAME", { target, value }];
const I = (msg: string): L => ["INFO", { msg }];
const ST = (msg: string): L => ["STEP", { msg }];

const SAMPLE: Record<string, { lines: L[]; result: Record<string, unknown> }> = {
  "restore-point": { lines: [ST("Creating a System Restore point"), C("System Restore point", "None", "Before OmniBoost")], result: { status: "done", summary: "Restore point created" } },
  "clean-temp": { lines: [ST("Cleaning Windows temp folder"), C("Windows temp folder", "1.24 GB", "18 MB"), C("Temp files (Aris)", "3.81 GB", "142 MB"), C("Error reports (archive)", "212 MB", "0 B"), C("Full memory dump", "1.02 GB", "deleted")], result: { status: "done", summary: "Freed 6.12 GB", freedBytes: 6.12 * 1024 ** 3 } },
  "clean-browser": { lines: [I("Chrome is open. Close it to clean its cache next time."), ST("Cleaning Edge cache"), C("Edge Cache (Default)", "642 MB", "0 B"), C("Edge GPUCache (Default)", "38 MB", "0 B")], result: { status: "done", summary: "Freed 680 MB", freedBytes: 680 * 1024 ** 2 } },
  "ram-standby": { lines: [ST("Purging the standby list"), C("Standby cache", "9.84 GB", "412 MB"), C("Free RAM", "2.10 GB", "11.52 GB")], result: { status: "done", summary: "Freed 9.42 GB of RAM" } },
  pagefile: { lines: [I("Installed RAM: 32 GB"), S("Page file", "System managed")], result: { status: "done", summary: "Page file already optimal" } },
  "power-plan": { lines: [ST("Creating the OmniBoost Ultimate power plan"), C("Minimum CPU state", "5%", "100%"), S("Maximum CPU state", "100%"), C("CPU cores kept awake (no parking)", "10%", "100%"), C("USB selective suspend", "On", "Off"), C("PCIe link power saving", "Moderate", "Off"), C("Turn off hard disk after", "1200 s", "Never"), C("Power plan", "Balanced", "OmniBoost Ultimate")], result: { status: "done", summary: "OmniBoost Ultimate power plan active" } },
  "power-throttling": { lines: [C("Power throttling", "On", "Off", "HKLM\\SYSTEM\\CurrentControlSet\\Control\\Power\\PowerThrottling\\PowerThrottlingOff")], result: { status: "done", summary: "Power throttling disabled" } },
  "game-mode": { lines: [S("Game Mode", "On"), C("Game Mode automatic switching", "Default", "On", "HKCU\\Software\\Microsoft\\GameBar\\AllowAutoGameMode")], result: { status: "done", summary: "Game Mode on" } },
  mmcss: { lines: [C("Network throttling", "On (10)", "Off", "HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Multimedia\\SystemProfile\\NetworkThrottlingIndex"), C("CPU reserved for background tasks", "20%", "10%"), C("Games: GPU priority", "8", "8"), C("Games: scheduling category", "Medium", "High"), C("Games: disk I/O priority", "Normal", "High")], result: { status: "done", summary: "Game scheduling profile applied", reboot: true } },
  "game-priority": { lines: [ST("Prioritizing Counter-Strike 2"), C("Counter-Strike 2: graphics preference", "Let Windows decide", "High performance"), C("Counter-Strike 2: CPU priority", "Normal", "High"), ST("Prioritizing Lineage II"), C("Lineage II: graphics preference", "Let Windows decide", "High performance"), C("Lineage II: CPU priority", "Normal", "High"), C("VALORANT: graphics preference", "Let Windows decide", "High performance"), I("VALORANT: CPU priority left to Riot Vanguard")], result: { status: "done", summary: "5 games set to high performance" } },
  hags: { lines: [C("Hardware-accelerated GPU scheduling", "Off", "On", "HKLM\\SYSTEM\\CurrentControlSet\\Control\\GraphicsDrivers\\HwSchMode")], result: { status: "done", summary: "GPU scheduling on (applies after restart)", reboot: true } },
  "nvidia-profile": { lines: [ST("Writing NVIDIA global profile"), C("Power management mode", "Normal", "Prefer maximum performance"), C("Low Latency Mode", "Off", "On"), C("Texture filtering quality", "Quality", "High performance")], result: { status: "done", summary: "NVIDIA profile tuned for performance" } },
  "gpu-driver": { lines: [["WARN", { msg: "NVIDIA GeForce RTX 5080 driver 576.88 is 207 days old" }]], result: { status: "manual", summary: "GPU driver update available", manual: [{ title: "Update NVIDIA driver", detail: "NVIDIA GeForce RTX 5080 runs 576.88 from 207 days ago. Install the latest Game Ready driver, then run Boost again to re-apply GPU settings.", open: "https://www.nvidia.com/en-us/drivers/" }] } },
  "display-refresh": { lines: [ST("Switching ASUS VG27AQ3A to 180 Hz"), C("ASUS VG27AQ3A (2560x1440) refresh rate", "60 Hz", "180 Hz"), S("DELL P2422H (1920x1080) refresh rate", "60 Hz (max)")], result: { status: "done", summary: "1 display(s) switched to max refresh rate" } },
  "display-vrr": { lines: [C("Windowed game optimizations + VRR", "(not set)", "VRROptimizeEnable=1;SwapEffectUpgradeEnable=1;")], result: { status: "done", summary: "VRR and windowed game optimizations on" } },
  "visual-effects": { lines: [C("Visual effects mode", "Let Windows choose", "Custom (OmniBoost)"), C("Taskbar animations", "On", "Off"), C("Animate menus", "On", "Off"), C("Fade menus", "On", "Off"), C("Shadows under windows", "On", "Off"), C("Animate controls inside windows", "On", "Off"), C("Animate windows when minimizing and maximizing", "On", "Off"), S("Smooth edges of screen fonts", "On")], result: { status: "done", summary: "Visual effects set for performance" } },
  transparency: { lines: [C("Transparency effects", "On", "Off")], result: { status: "done", summary: "Transparency effects off" } },
  "startup-apps": { lines: [C("Startup: Spotify", "Enabled", "Disabled"), C("Startup: Discord", "Enabled", "Disabled"), C("Startup: EpicGamesLauncher", "Enabled", "Disabled"), C("Startup: Microsoft Teams", "Enabled", "Disabled"), S("Startup: SecurityHealth", "Kept (driver, security or device app)"), S("Startup: LGHUB", "Kept (driver, security or device app)"), C("Startup: CCleaner Monitoring", "Enabled", "Disabled")], result: { status: "done", summary: "9 startup apps disabled, 4 essential kept" } },
  "background-apps": { lines: [C("Store apps running in background", "Allowed", "Blocked"), C("Widgets board", "On", "Off"), C("Telemetry service (DiagTrack)", "Auto", "Manual (stopped)"), C("Downloaded Maps Manager", "Auto", "Manual (stopped)")], result: { status: "done", summary: "Background apps and telemetry trimmed" } },
  overlays: { lines: [C("Xbox Game Bar background recording", "On", "Off"), C("Xbox Game Bar captures", "On", "Off"), C("Game DVR (system policy)", "Allowed", "Blocked")], result: { status: "done", summary: "Xbox Game Bar recording off", manual: [{ title: "Steam overlay", detail: "Steam > Settings > In Game > turn off \"Enable the Steam Overlay while in-game\".", open: "steam://open/settings" }, { title: "Discord overlay", detail: "Discord > User Settings > Game Overlay > turn off \"Enable in-game overlay\"." }] } },
  notifications: { lines: [C("Pop-up notifications", "On", "Off"), C("Windows tips and suggestions", "On", "Off")], result: { status: "done", summary: "Notifications silenced" } },
  "discord-hwaccel": { lines: [ST("Closing Discord to apply"), C("Discord hardware acceleration", "On", "Off"), I("Reopened Discord")], result: { status: "done", summary: "Discord no longer uses the GPU" } },
  "browser-background": { lines: [C("Chrome keeps running after close", "On", "Off"), C("Edge keeps running after close", "On", "Off"), C("Edge startup boost (preloads at boot)", "On", "Off")], result: { status: "done", summary: "Browsers stop running in the background" } },
  "net-tcp": { lines: [C("DNS resolver cache", "Cached entries", "Flushed"), S("TCP receive window auto-tuning", "Normal"), S("Receive Side Scaling (multi-core networking)", "Enabled"), S("Forced HPET timer (bcdedit useplatformclock)", "Not forced (Windows default)")], result: { status: "done", summary: "Network stack tuned" } },
  "net-nagle": { lines: [C("Ethernet: delayed ACK", "On", "Off (ack every packet)"), C("Ethernet: Nagle's algorithm", "On", "Off")], result: { status: "done", summary: "Nagle off on 1 connection(s)", reboot: true } },
  "net-adapter": { lines: [ST("Updating Ethernet: Energy-Efficient Ethernet (connection drops for a few seconds)"), C("Ethernet: Energy-Efficient Ethernet", "Enabled", "Disabled"), C("Ethernet: Green Ethernet", "Enabled", "Disabled")], result: { status: "done", summary: "2 adapter power-saving features off" } },
  "disk-scan": { lines: [S("Samsung SSD 990 PRO 2TB health", "Healthy, 3% wear, 41 C"), S("ST2000DM008-2FR102 health", "Healthy, 34 C"), ST("Scanning drive C: for file system errors"), S("Drive C: file system", "No errors"), S("Drive D: file system", "No errors")], result: { status: "done", summary: "2 drives scanned, no errors" } },
  "disk-optimize": { lines: [ST("Running TRIM on drive C: (SSD)"), C("Drive C: (SSD)", "Unused blocks pending", "TRIM complete"), S("Drive D: (HDD)", "3% fragmented, no defrag needed")], result: { status: "done", summary: "2 drive(s) optimized" } },
  "drivers-oem": { lines: [ST("Searching Windows Update for driver updates. This can take a few minutes"), I("2 driver update(s) found"), ST("Installing AMD - System - 6.1.0.123"), C("AMD - System - 6.1.0.123", "Outdated", "Installed (2026-08-02)"), C("Realtek - Audio - 6.0.9785.1", "Outdated", "Installed (2026-06-11)")], result: { status: "done", summary: "2 of 2 driver updates installed", reboot: true } },
  "background-processes": { lines: [ST("Checking running processes"), C("Phone Link (PhoneExperienceHost.exe)", "Running, 96 MB", "Stopped"), C("Xbox Game Bar (GameBar.exe)", "Running, 61 MB", "Stopped"), C("Microsoft Edge (no window open) (msedge.exe)", "7 processes, 412 MB", "Stopped"), C("Adobe Creative Cloud Experience (CCXProcess.exe)", "Running, 74 MB", "Stopped"), C("Google Update service", "Auto", "Manual (stopped)"), C("Telemetry task: Microsoft Compatibility Appraiser", "Ready", "Disabled"), C("Telemetry task: Consolidator", "Ready", "Disabled"), I("Left running: Corsair iCUE (iCUE.exe) uses 310 MB. Not on the safe list.")], result: { status: "done", summary: "4 processes stopped (643 MB RAM), 1 updater services set to Manual, 2 telemetry tasks off" } },
  "clean-components": { lines: [ST("Starting DISM component cleanup"), ["STEP", { msg: "Cleaning the component store, 10%, 21s", pct: 10 }], ["STEP", { msg: "Cleaning the component store, 34%, 1m 05s", pct: 34 }], ["STEP", { msg: "Cleaning the component store, 61%, 1m 52s", pct: 61 }], ["STEP", { msg: "Cleaning the component store, 88%, 2m 40s", pct: 88 }], ["STEP", { msg: "Cleaning the component store, 100%, 3m 02s", pct: 100 }], I("Component store cleaned"), C("Free space on C:", "425.8 GB", "428.9 GB")], result: { status: "done", summary: "Freed 3.10 GB", freedBytes: 3.1 * 1024 ** 3 } },
  "clean-disk": { lines: [I("Disk Cleanup will clear 18 categories. Previous Windows installs, the Recycle Bin and shader caches are kept."), ST("Running Windows Disk Cleanup"), ST("Running Windows Disk Cleanup, 6s, 120 MB freed so far"), ST("Running Windows Disk Cleanup, 14s, 410 MB freed so far"), ST("Running Windows Disk Cleanup, 22s, 640 MB freed so far"), ST("Running Windows Disk Cleanup, 31s, 1.12 GB freed so far"), ST("Running Windows Disk Cleanup, 40s, 1.35 GB freed so far"), C("Free space on C:", "418.6 GB", "419.9 GB")], result: { status: "done", summary: "Freed 1.35 GB", freedBytes: 1.35 * 1024 ** 3 } },
  "clean-update": { lines: [ST("Clearing the Windows Update download cache"), C("Windows Update downloads", "2.41 GB", "0 B"), ST("Clearing the Delivery Optimization cache"), I("Delivery Optimization cache cleared"), C("Free space on C:", "419.9 GB", "422.6 GB")], result: { status: "done", summary: "Freed 2.70 GB", freedBytes: 2.7 * 1024 ** 3 } },
};

// A setting re-checked by the verify batch: what was applied shows as already in place,
// except a couple that Windows or a driver update changed back.
const DRIFT: Record<string, L> = {
  "power-plan": C("Power plan", "Balanced", "OmniBoost Ultimate"),
  "nvidia-profile": C("Power management mode", "Normal", "Prefer maximum performance"),
};
function verifyLines(id: string): L[] {
  const src = SAMPLE[id]?.lines ?? [];
  const out: L[] = src.filter((l) => l[0] === "CHANGE").map((l) => S(String(l[1].target), String(l[1].after)));
  if (DRIFT[id]) out.push(DRIFT[id]);
  return out.length ? out : [S(id, "In place")];
}

async function play(id: string, lines: L[], result: Record<string, unknown>, idx: number, total: number, fast = false) {
  emit({ type: "start", id, index: idx, total });
  const t = Date.now();
  let stopped = false;
  for (const [kind, data] of lines) {
    await sleep(fast ? 70 : kind === "STEP" ? 420 : 230);
    if (skipRequested) { stopped = true; break; }
    emit({ type: "line", id, kind, data });
  }
  if (stopped) {
    skipRequested = false;
    emit({ type: "line", id, kind: "INFO", data: { msg: "Stopped. Space freed so far is kept." } });
    emit({ type: "end", id, result: { status: "skipped", summary: "Stopped early, freed 640 MB", freedBytes: 640 * 1024 ** 2 }, elapsedMs: Date.now() - t });
    return { status: "skipped" };
  }
  await sleep(fast ? 60 : 250);
  const changes = lines.filter((l) => l[0] === "CHANGE").length;
  const r = { changes, ...result } as never;
  emit({ type: "end", id, result: r, elapsedMs: Date.now() - t });
  return r as { status: string };
}

export async function runBoost(ids: string[], verify: string[], options: { restorePoint: boolean }) {
  const t0 = Date.now();
  const total = (options.restorePoint ? 1 : 0) + verify.length + ids.length;
  const rec: LastRun = { version: "1.0.2", startedAt: t0, finishedAt: null, planned: [], current: null, steps: { ...(record?.steps ?? {}) } };
  record = rec;
  (async () => {
    let i = 0;
    if (options.restorePoint) {
      const r = await play("restore-point", SAMPLE["restore-point"].lines, SAMPLE["restore-point"].result, i++, total);
      rec.steps["restore-point"] = { status: r.status as never, summary: "Restore point created", endedAt: Date.now(), via: "run" };
    }
    for (const id of verify) {
      const r = await play(`verify:${id}`, verifyLines(id), { status: "done", summary: DRIFT[id] ? "Drift repaired" : "Verified" }, i++, total, true);
      rec.steps[id] = { status: r.status as never, summary: "Verified", endedAt: Date.now(), via: "verify" };
    }
    for (const id of ids) {
      const s = SAMPLE[id] ?? { lines: [I("Applied")], result: { status: "done", summary: "Done" } };
      const r = await play(id, s.lines, s.result, i++, total);
      rec.steps[id] = { status: r.status as never, summary: String(s.result.summary ?? "Done"), endedAt: Date.now(), via: "run" };
    }
    rec.finishedAt = Date.now();
    backups = 1;
    emit({ type: "done", elapsedMs: Date.now() - t0 });
  })();
}

export async function skip() {
  skipRequested = true;
}

export async function lastRun() {
  return record;
}

export async function revert() {
  const t0 = Date.now();
  (async () => {
    emit({ type: "start", id: "revert", index: 0, total: 1 });
    for (const [t, b, a] of [["Power plan", "OmniBoost Ultimate", "Balanced"], ["Hardware-accelerated GPU scheduling", "On", "Off"], ["ASUS VG27AQ3A refresh rate", "180 Hz", "60 Hz"], ["Startup: Spotify", "Disabled", "Enabled"]]) {
      await sleep(300);
      emit({ type: "line", id: "revert", kind: "CHANGE", data: { target: t, before: b, after: a } });
    }
    backups = 0;
    record = null;
    emit({ type: "end", id: "revert", result: { status: "done", summary: "All OmniBoost changes were undone", reboot: true }, elapsedMs: Date.now() - t0 });
    emit({ type: "done", elapsedMs: Date.now() - t0 });
  })();
}

export async function backupCount() {
  return backups || (record ? 1 : 0);
}
