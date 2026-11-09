# OmniBoost

One-click Windows performance optimizer for gaming. Scans the PC, finds hardware problems, applies 37 reversible optimizations and shows every change live as it happens.

Tauri 2 + React UI, Rust core, PowerShell engine. Runs elevated. Every original value is journaled, so one click undoes everything.

## Features

- **Diagnostics:** temperatures, single-channel or misplaced RAM, XMP/EXPO off, GPU PCIe lane drop, WHEA hardware errors, unexpected shutdowns, drive health and wear, outdated GPU drivers, devices with driver errors.
- **Power and CPU:** Ultimate Performance plan, 100% minimum CPU state, core parking off, USB/PCIe/Wi-Fi power saving off, power throttling off. Safe path for Modern Standby laptops and dual-CCD X3D CPUs.
- **Graphics and display:** NVIDIA global profile (max performance, low latency, texture filtering), optional G-SYNC FPS cap, AMD checklist, HAGS, highest refresh rate per monitor, VRR, visual effects and transparency.
- **Gaming:** Game Mode, multimedia scheduler game profile, Steam, Epic and Riot games detected and set to high performance GPU and high CPU priority.
- **Background:** startup apps, background apps, Widgets / News and interests, telemetry services and tasks, useless background processes, overlays, notifications, Discord and browser background/GPU use.
- **Network:** DNS flush, TCP auto-tuning, RSS, forced HPET removed, Nagle off, adapter power saving off.
- **Cleanup and storage:** temp files, browser caches, Disk Cleanup, Windows Update cache, optional DISM component cleanup, SMART and file system scan, TRIM / defrag only when needed.
- **Drivers:** OEM driver updates from Windows Update (GPU drivers skipped), GPU driver age check.
- **Every boost builds on the last one:** progress is saved after every step. An interrupted boost resumes where it stopped. The next boost re-checks everything earlier boosts applied in one fast pass, repairs anything Windows or a driver update changed back, then runs only what is left.
- **Skip** on long steps, live progress and freed-space counters.

Windows 10 (22H2) and Windows 11, 64-bit.

## Build

Windows (MSVC):

    npm install
    npx tauri build --bundles nsis

Output: `src-tauri/target/release/bundle/nsis/OmniBoost_<version>_x64-setup.exe`

Dev with hot reload (run the terminal as Administrator, the exe requests elevation):

    npx tauri dev

UI only, in a browser with sample data (`?fresh` starts without a previous boost):

    npm run dev

Linux cross-build (target `x86_64-pc-windows-gnu`, mingw-w64 and NSIS installed):

    npx tauri build --target x86_64-pc-windows-gnu --bundles nsis

CI: `.github/workflows/build.yml` builds the installer on `windows-latest` for every `v*` tag.

## Architecture

    src/                              React UI: dashboard, Boost plan modal, live change feed
    src-tauri/src/lib.rs              Commands: scan, start_monitor, run_boost, revert_all, skip_step, last_run, backup_count, open_target, restart_pc
    src-tauri/app.manifest            requireAdministrator
    src-tauri/scripts/common.ps1      Protocol, undo journal, registry helpers, skip flag, native helpers (display, NVAPI DRS, power, memory)
    src-tauri/scripts/scan.ps1        Hardware scan and diagnostics -> @@SCAN json
    src-tauri/scripts/monitor.ps1     Live CPU/GPU/RAM/temps every 2 s -> @@MON json
    src-tauri/scripts/revert.ps1      Replays the undo journal in reverse
    src-tauri/scripts/restore-point.ps1  System Restore point before a boost
    src-tauri/scripts/tweaks/         One script per optimization
    src-tauri/scripts/tweaks.json     Plan metadata: title, category, default, timeout, skippable, repeat

Protocol: each script prints `@@KIND {json}` lines. Kinds: STEP (optional `pct`), CHANGE, SAME, INFO, WARN, RESULT. The verify batch adds BEGIN and END around each re-checked step. Rust forwards everything as `boost://event`.

State on the PC:

- `%ProgramData%\OmniBoost\backup.json` undo journal. Only the first original value of each setting is kept.
- `%ProgramData%\OmniBoost\last-run.json` run record: planned steps, current step, result and time of every step.

`repeat` in `tweaks.json`: `verify` steps are re-checked in the fast batch once applied, `always` steps run every boost, `once` steps are skipped while they completed in the last 7 days.

## Adding a tweak

1. Add `src-tauri/scripts/tweaks/<id>.ps1`. Use `Set-Reg` (journaled automatically) or `Add-Backup` with a matching branch in `revert.ps1`. Make it idempotent: report `Same` when nothing needs to change.
2. End with `Result -Summary '...'`.
3. Add an entry to `tweaks.json`. Array order is run order.

## Roadmap

- Code signing (EV certificate) so SmartScreen stops warning.
- Fan control (LibreHardwareMonitor + PawnIO).
- AMD settings through an ADLX native helper.
- Game session mode: boost on game launch, restore on exit.
