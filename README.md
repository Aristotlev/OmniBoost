# OmniBoost

**One click to a faster PC.** OmniBoost scans your Windows PC, finds what slows it down, and applies 37 optimizations for gaming and work, showing every change live as it happens. One click undoes all of it.

<p>
  <a href="https://github.com/Aristotlev/OmniBoost/releases/latest/download/OmniBoost-Windows.exe"><b>⬇ Download for Windows</b></a>
</p>

Windows 10 (22H2) and Windows 11, 64-bit. Free. Once installed, OmniBoost updates itself.

## What you get

- **Health check:** temperatures, RAM in the wrong slots or running slow (XMP/EXPO off), graphics card running below full speed, hardware errors, unexpected shutdowns, drive health and wear, outdated graphics drivers, devices with driver problems.
- **Power and CPU:** the fastest power plan, full CPU speed, no power saving on USB, PCIe and Wi-Fi. Laptops and dual-CCD X3D CPUs get a safe setup of their own.
- **Graphics and display:** NVIDIA settings for maximum performance and low latency, optional G-SYNC FPS cap, AMD checklist, the highest refresh rate on every monitor, variable refresh rate, lighter visual effects.
- **Gaming:** Game Mode on, and your Steam, Epic and Riot games set to use the fast graphics card and high CPU priority.
- **Background:** fewer startup and background apps, Widgets and News off, telemetry off, overlays and notifications quieted, Discord and browsers kept from using the GPU in the background.
- **Network:** network settings tuned for low latency.
- **Cleanup and storage:** temp files, browser caches, Windows Update leftovers, drive health check, TRIM or defrag only when needed.
- **Drivers:** driver updates from Windows Update (graphics drivers are left to you, with a check of how old they are).
- **Every boost builds on the last:** an interrupted boost picks up where it stopped. The next boost checks everything earlier boosts set, fixes anything Windows or a driver update changed back, then runs only what is left.

## First launch

OmniBoost is new and not yet signed with a paid Microsoft certificate, so Windows asks once before opening it:

1. Run `OmniBoost-Windows.exe`. If you see "Windows protected your PC", click **More info**, then **Run anyway**.
2. OmniBoost asks for administrator permission because it changes Windows settings. Click **Yes**.
3. Click **Boost my PC**.

## Undo

OmniBoost saves the original value of every setting it changes, and by default creates a System Restore point before a boost. **Undo all OmniBoost changes** in the app puts everything back.

## Privacy

Everything stays on your PC. OmniBoost has no accounts, no servers and no analytics.

[Report a problem](https://github.com/Aristotlev/OmniBoost/issues)

## FAQ

**How do updates work?**
OmniBoost checks for a new version when it opens and every 6 hours, and installs it in one click. Your undo history is kept.

---

<details>
<summary><b>For developers</b></summary>

Tauri 2 + React UI, Rust core, PowerShell engine. Runs elevated. Every original value is journaled, so one click undoes everything.

### Build

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

### Release

Bump the version in `package.json`, `src-tauri/tauri.conf.json` and `src-tauri/Cargo.toml`, commit, then push a tag:

    git tag v1.0.3
    git push origin v1.0.3

GitHub Actions (`.github/workflows/release.yml`) builds the signed installer on `windows-latest`, publishes the release with `latest.json` for the updater, and attaches the fixed-name download `OmniBoost-Windows.exe` that the download button points at. Installed copies (1.0.2 and newer) update themselves.

The update signing key is `~/.tauri/omniboost.key` (password in `~/.tauri/omniboost.key.password`), also saved as the repo secrets `TAURI_SIGNING_PRIVATE_KEY` and `TAURI_SIGNING_PRIVATE_KEY_PASSWORD`. Back it up: without it, installed copies can't verify new updates.

### Architecture

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
    docs/                             website: https://aristotlev.github.io/OmniBoost/

Protocol: each script prints `@@KIND {json}` lines. Kinds: STEP (optional `pct`), CHANGE, SAME, INFO, WARN, RESULT. The verify batch adds BEGIN and END around each re-checked step. Rust forwards everything as `boost://event`.

State on the PC:

- `%ProgramData%\OmniBoost\backup.json` undo journal. Only the first original value of each setting is kept.
- `%ProgramData%\OmniBoost\last-run.json` run record: planned steps, current step, result and time of every step.

`repeat` in `tweaks.json`: `verify` steps are re-checked in the fast batch once applied, `always` steps run every boost, `once` steps are skipped while they completed in the last 7 days.

### Detailed optimization list

- **Diagnostics:** temperatures, single-channel or misplaced RAM, XMP/EXPO off, GPU PCIe lane drop, WHEA hardware errors, unexpected shutdowns, drive health and wear, outdated GPU drivers, devices with driver errors.
- **Power and CPU:** Ultimate Performance plan, 100% minimum CPU state, core parking off, USB/PCIe/Wi-Fi power saving off, power throttling off. Safe path for Modern Standby laptops and dual-CCD X3D CPUs.
- **Graphics and display:** NVIDIA global profile (max performance, low latency, texture filtering), optional G-SYNC FPS cap, AMD checklist, HAGS, highest refresh rate per monitor, VRR, visual effects and transparency.
- **Gaming:** Game Mode, multimedia scheduler game profile, Steam, Epic and Riot games detected and set to high performance GPU and high CPU priority.
- **Background:** startup apps, background apps, Widgets / News and interests, telemetry services and tasks, useless background processes, overlays, notifications, Discord and browser background/GPU use.
- **Network:** DNS flush, TCP auto-tuning, RSS, forced HPET removed, Nagle off, adapter power saving off.
- **Cleanup and storage:** temp files, browser caches, Disk Cleanup, Windows Update cache, optional DISM component cleanup, SMART and file system scan, TRIM / defrag only when needed.
- **Drivers:** OEM driver updates from Windows Update (GPU drivers skipped), GPU driver age check.

### Adding a tweak

1. Add `src-tauri/scripts/tweaks/<id>.ps1`. Use `Set-Reg` (journaled automatically) or `Add-Backup` with a matching branch in `revert.ps1`. Make it idempotent: report `Same` when nothing needs to change.
2. End with `Result -Summary '...'`.
3. Add an entry to `tweaks.json`. Array order is run order.

### Roadmap

- Code signing (EV certificate) so SmartScreen stops warning.
- Fan control (LibreHardwareMonitor + PawnIO).
- AMD settings through an ADLX native helper.
- Game session mode: boost on game launch, restore on exit.

</details>
