//! OmniBoost backend: runs the embedded PowerShell engine elevated and streams
//! every change to the UI as events.

use serde_json::{json, Value};
use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{mpsc, Mutex};
use std::thread;
use std::time::{Duration, Instant};
use tauri::{AppHandle, Emitter, State};

include!(concat!(env!("OUT_DIR"), "/scripts.rs"));

const COMMON: &str = include_str!("../scripts/common.ps1");
const SCAN: &str = include_str!("../scripts/scan.ps1");
const MONITOR: &str = include_str!("../scripts/monitor.ps1");
const REVERT: &str = include_str!("../scripts/revert.ps1");
const RESTORE_POINT: &str = include_str!("../scripts/restore-point.ps1");
const MANIFEST: &str = include_str!("../scripts/tweaks.json");

#[derive(Default)]
struct AppState {
    busy: AtomicBool,
    monitor: AtomicBool,
    /// Set when the user presses "Skip this step". Scripts get a few seconds to stop
    /// cleanly (they poll the skip flag file); after that the step is force-stopped.
    skip_at: Mutex<Option<Instant>>,
}

fn skip_flag_path() -> PathBuf {
    program_data().join("run").join("skip.flag")
}

fn clear_skip(st: &AppState) {
    if let Ok(mut g) = st.skip_at.lock() {
        *g = None;
    }
    let _ = std::fs::remove_file(skip_flag_path());
}

fn program_data() -> PathBuf {
    PathBuf::from(std::env::var("ProgramData").unwrap_or_else(|_| "C:\\ProgramData".into())).join("OmniBoost")
}

fn system_root() -> PathBuf {
    PathBuf::from(std::env::var("SystemRoot").unwrap_or_else(|_| "C:\\Windows".into()))
}

/// Writes common helpers + script body to a temp .ps1 (UTF-8 with BOM, CRLF).
fn write_script(name: &str, body: &str) -> Result<PathBuf, String> {
    let dir = program_data().join("run");
    std::fs::create_dir_all(&dir).map_err(|e| format!("create {}: {e}", dir.display()))?;
    let path = dir.join(format!("{name}-{}.ps1", std::process::id()));
    let mut text = String::with_capacity(COMMON.len() + body.len() + 8);
    text.push('\u{FEFF}');
    text.push_str(COMMON);
    text.push_str("\n\n");
    text.push_str(body);
    let text = text.replace("\r\n", "\n").replace('\n', "\r\n");
    std::fs::write(&path, text).map_err(|e| format!("write {}: {e}", path.display()))?;
    Ok(path)
}

fn hidden(cmd: &mut Command) {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(0x0800_0000); // CREATE_NO_WINDOW
    }
    #[cfg(not(windows))]
    let _ = cmd;
}

fn kill_tree(pid: u32) {
    let mut c = Command::new(system_root().join("System32").join("taskkill.exe"));
    c.args(["/T", "/F", "/PID", &pid.to_string()]).stdout(Stdio::null()).stderr(Stdio::null());
    hidden(&mut c);
    let _ = c.status();
}

/// Runs one engine script and forwards every `@@KIND {json}` line to `on_line`.
/// Returns the process exit code (-2 on timeout).
fn run_streaming<F: FnMut(&str, Value)>(
    name: &str,
    body: &str,
    tweak: &str,
    options: &Value,
    timeout: Duration,
    ctl: Option<&AppState>,
    mut on_line: F,
) -> Result<i32, String> {
    let path = write_script(name, body)?;
    let ps = system_root().join("System32").join("WindowsPowerShell").join("v1.0").join("powershell.exe");
    let mut cmd = Command::new(ps);
    cmd.args(["-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File"])
        .arg(&path)
        .env("OMNIBOOST_TWEAK", tweak)
        .env("OMNIBOOST_OPTIONS", options.to_string())
        .env("OMNIBOOST_PARENT", std::process::id().to_string())
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    hidden(&mut cmd);
    let mut child = cmd.spawn().map_err(|e| format!("Could not start PowerShell: {e}"))?;
    let stdout = child.stdout.take().ok_or("no stdout")?;
    let stderr = child.stderr.take().ok_or("no stderr")?;

    let (tx, rx) = mpsc::channel::<(String, Value)>();
    let tx_err = tx.clone();
    thread::spawn(move || {
        let mut r = BufReader::new(stdout);
        let mut buf = Vec::new();
        loop {
            buf.clear();
            match r.read_until(b'\n', &mut buf) {
                Ok(0) | Err(_) => break,
                Ok(_) => {
                    let line = String::from_utf8_lossy(&buf);
                    let line = line.trim().trim_start_matches('\u{FEFF}');
                    if let Some(rest) = line.strip_prefix("@@") {
                        let (kind, payload) = rest.split_once(' ').unwrap_or((rest, "{}"));
                        let v = serde_json::from_str(payload).unwrap_or_else(|_| json!({ "msg": payload }));
                        if tx.send((kind.to_string(), v)).is_err() {
                            break;
                        }
                    }
                }
            }
        }
    });
    thread::spawn(move || {
        let r = BufReader::new(stderr);
        let mut n = 0;
        for line in r.lines().map_while(Result::ok) {
            let l = line.trim();
            if l.is_empty() || n >= 12 {
                continue;
            }
            n += 1;
            let msg: String = l.chars().take(240).collect();
            let _ = tx_err.send(("STDERR".into(), json!({ "msg": msg })));
        }
    });

    let start = Instant::now();
    let exit;
    loop {
        while let Ok((k, v)) = rx.try_recv() {
            on_line(&k, v);
        }
        match child.try_wait() {
            Ok(Some(st)) => {
                exit = st.code().unwrap_or(-1);
                break;
            }
            Ok(None) => {}
            Err(_) => {
                exit = -1;
                break;
            }
        }
        if let Some(st) = ctl {
            let due = st
                .skip_at
                .lock()
                .map(|g| g.as_ref().map(|t| t.elapsed() > Duration::from_secs(6)).unwrap_or(false))
                .unwrap_or(false);
            if due {
                kill_tree(child.id());
                on_line("WARN", json!({ "msg": "Stopped by you" }));
                exit = -3;
                break;
            }
        }
        if start.elapsed() > timeout {
            kill_tree(child.id());
            on_line("WARN", json!({ "msg": format!("Stopped after {} s (time limit)", timeout.as_secs()) }));
            exit = -2;
            break;
        }
        thread::sleep(Duration::from_millis(50));
    }
    // Drain what the reader threads still hold, without waiting on grandchildren.
    let drain_until = Instant::now() + Duration::from_millis(1500);
    loop {
        match rx.recv_timeout(Duration::from_millis(100)) {
            Ok((k, v)) => on_line(&k, v),
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
            Err(mpsc::RecvTimeoutError::Timeout) => {
                if Instant::now() > drain_until {
                    break;
                }
            }
        }
    }
    let _ = std::fs::remove_file(&path);
    Ok(exit)
}

fn manifest() -> Value {
    serde_json::from_str(MANIFEST).unwrap_or_else(|_| json!([]))
}

fn script_for(id: &str) -> Option<&'static str> {
    match id {
        "restore-point" => Some(RESTORE_POINT),
        _ => TWEAK_SCRIPTS.iter().find(|(k, _)| *k == id).map(|(_, s)| *s),
    }
}

#[tauri::command]
fn get_tweaks() -> Value {
    manifest()
}

#[tauri::command]
async fn scan(app: AppHandle) -> Result<Value, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let mut report: Option<Value> = None;
        let exit = run_streaming("scan", SCAN, "scan", &json!({}), Duration::from_secs(240), None, |kind, v| match kind {
            "SCAN" => report = Some(v),
            "STEP" => {
                let _ = app.emit("scan://step", v);
            }
            _ => {}
        })?;
        report.ok_or_else(|| format!("Scan returned no data (exit {exit})"))
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
fn start_monitor(app: AppHandle, state: State<'_, AppState>) {
    if state.monitor.swap(true, Ordering::SeqCst) {
        return;
    }
    thread::spawn(move || {
        // The script exits by itself when this process is gone.
        let _ = run_streaming("monitor", MONITOR, "monitor", &json!({}), Duration::from_secs(60 * 60 * 24 * 30), None, |kind, v| {
            if kind == "MON" {
                let _ = app.emit("monitor://tick", v);
            }
        });
    });
}

// ---------- run record: what every boost did, so the next one can verify and resume ----------

fn now_ms() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

fn last_run_path() -> PathBuf {
    program_data().join("last-run.json")
}

/// The saved run record. Without one (first boost on this version), it is rebuilt
/// from the undo journal so earlier changes still get verified.
fn load_last_run() -> Value {
    if let Ok(t) = std::fs::read_to_string(last_run_path()) {
        if let Ok(v) = serde_json::from_str::<Value>(t.trim_start_matches('\u{FEFF}')) {
            if v.is_object() {
                return v;
            }
        }
    }
    let mut steps = serde_json::Map::new();
    if let Ok(t) = std::fs::read_to_string(program_data().join("backup.json")) {
        if let Ok(v) = serde_json::from_str::<Value>(t.trim_start_matches('\u{FEFF}')) {
            let list = match v {
                Value::Array(a) => a,
                o @ Value::Object(_) => vec![o],
                _ => vec![],
            };
            for e in list {
                let Some(id) = e["tweak"].as_str() else { continue };
                if script_for(id).is_none() {
                    continue;
                }
                let time = e["time"].as_str().unwrap_or("").to_string();
                let newer = steps.get(id).and_then(|x| x["endedAtLocal"].as_str()).map(|x| x < time.as_str()).unwrap_or(true);
                if newer {
                    steps.insert(id.to_string(), json!({ "status": "done", "summary": "Applied in an earlier boost", "endedAtLocal": time, "via": "journal" }));
                }
            }
        }
    }
    if steps.is_empty() {
        return Value::Null;
    }
    json!({ "synthetic": true, "startedAt": null, "finishedAt": null, "planned": [], "current": null, "steps": Value::Object(steps) })
}

fn save_last_run(rec: &Value) {
    let p = last_run_path();
    let tmp = p.with_extension("json.tmp");
    if let Ok(t) = serde_json::to_string_pretty(rec) {
        if std::fs::write(&tmp, t).is_ok() {
            let _ = std::fs::rename(&tmp, &p);
        }
    }
}

fn record_step(rec: &mut Value, id: &str, result: &Value, elapsed_ms: u64, via: &str) {
    if !rec["steps"].is_object() {
        rec["steps"] = json!({});
    }
    rec["steps"][id] = json!({
        "status": result["status"].as_str().unwrap_or("done"),
        "summary": result["summary"].as_str().unwrap_or(""),
        "changes": result["changes"].as_u64().unwrap_or(0),
        "endedAt": now_ms(),
        "elapsedMs": elapsed_ms,
        "via": via,
    });
    rec["current"] = Value::Null;
    save_last_run(rec);
}

fn fallback_result(exit: Result<i32, String>) -> Value {
    match exit {
        Ok(0) => json!({ "status": "done", "summary": "Done" }),
        Ok(-2) => json!({ "status": "failed", "summary": "Timed out" }),
        Ok(-3) => json!({ "status": "skipped", "summary": "Skipped" }),
        Ok(code) => json!({ "status": "failed", "summary": format!("Exited with code {code}") }),
        Err(e) => json!({ "status": "failed", "summary": e }),
    }
}

enum PlanItem {
    /// One script in its own PowerShell process.
    One(String),
    /// Settings applied by earlier boosts, re-checked in one PowerShell process.
    Verify(Vec<String>),
}

/// All verify scripts in one process. Each runs in its own scope and is framed by
/// @@BEGIN / @@END markers so the UI still sees one step per setting.
fn build_verify_batch(ids: &[String]) -> String {
    let mut s = String::new();
    for id in ids {
        if let Some(body) = script_for(id) {
            s.push_str(&format!(
                "$OB_Tweak = '{id}'; $script:OB_Changes = 0\nEmit 'BEGIN' @{{ id = '{id}' }}\ntry {{ & {{\n{body}\n}} }} catch {{ Warn $_.Exception.Message }}\nEmit 'END' @{{ id = '{id}' }}\n\n"
            ));
        }
    }
    s
}

const CHANNEL: &str = "boost://event";

fn run_plan(app: AppHandle, plan: Vec<PlanItem>, options: Value, record_run: bool) {
    use tauri::Manager;
    let st = app.state::<AppState>();
    let man = manifest();
    let started = Instant::now();
    let total: usize = plan.iter().map(|p| match p { PlanItem::One(_) => 1, PlanItem::Verify(v) => v.len() }).sum();
    let mut rec = if record_run { load_last_run() } else { Value::Null };
    if record_run {
        if !rec.is_object() {
            rec = json!({ "steps": {} });
        }
        let planned: Vec<String> = plan
            .iter()
            .flat_map(|p| match p {
                PlanItem::One(id) => vec![id.clone()],
                PlanItem::Verify(v) => v.iter().map(|i| format!("verify:{i}")).collect(),
            })
            .collect();
        rec["version"] = json!(env!("CARGO_PKG_VERSION"));
        rec["synthetic"] = json!(false);
        rec["startedAt"] = json!(now_ms());
        rec["finishedAt"] = Value::Null;
        rec["planned"] = json!(planned);
        rec["options"] = options.clone();
        rec["current"] = Value::Null;
        save_last_run(&rec);
    }
    let mut index = 0usize;
    for item in plan {
        match item {
            PlanItem::One(id) => {
                let meta = man.as_array().and_then(|a| a.iter().find(|t| t["id"] == id.as_str())).cloned().unwrap_or(json!({}));
                let timeout = Duration::from_secs(meta["timeout"].as_u64().unwrap_or(300));
                let _ = app.emit(CHANNEL, json!({ "type": "start", "id": id, "index": index, "total": total }));
                index += 1;
                if record_run {
                    rec["current"] = json!(id);
                    save_last_run(&rec);
                }
                clear_skip(&st);
                let t0 = Instant::now();
                let mut result: Option<Value> = None;
                let body = if id == "revert" { Some(REVERT) } else { script_for(&id) };
                let exit = match body {
                    None => Err(format!("Unknown step {id}")),
                    Some(body) => run_streaming(&id, body, &id, &options, timeout, Some(&*st), |kind, data| {
                        if kind == "RESULT" {
                            result = Some(data.clone());
                        }
                        let _ = app.emit(CHANNEL, json!({ "type": "line", "id": id, "kind": kind, "data": data }));
                    }),
                };
                let result = result.unwrap_or_else(|| fallback_result(exit));
                clear_skip(&st);
                let ms = t0.elapsed().as_millis() as u64;
                if record_run {
                    record_step(&mut rec, &id, &result, ms, "run");
                }
                let _ = app.emit(CHANNEL, json!({ "type": "end", "id": id, "result": result, "elapsedMs": ms }));
            }
            PlanItem::Verify(ids) => {
                let body = build_verify_batch(&ids);
                let timeout = Duration::from_secs(120 + 60 * ids.len() as u64);
                let mut cur: Option<(String, Instant)> = None;
                let mut result: Option<Value> = None;
                let mut ended: Vec<String> = Vec::new();
                clear_skip(&st);
                let exit = run_streaming("verify", &body, "verify", &options, timeout, Some(&*st), |kind, data| match kind {
                    "BEGIN" => {
                        let id = data["id"].as_str().unwrap_or("").to_string();
                        let _ = app.emit(CHANNEL, json!({ "type": "start", "id": format!("verify:{id}"), "index": index, "total": total }));
                        index += 1;
                        if record_run {
                            rec["current"] = json!(format!("verify:{id}"));
                        }
                        result = None;
                        cur = Some((id, Instant::now()));
                    }
                    "END" => {
                        if let Some((id, t0)) = cur.take() {
                            let r = result.take().unwrap_or_else(|| json!({ "status": "done", "summary": "Verified" }));
                            let ms = t0.elapsed().as_millis() as u64;
                            if record_run {
                                record_step(&mut rec, &id, &r, ms, "verify");
                            }
                            let _ = app.emit(CHANNEL, json!({ "type": "end", "id": format!("verify:{id}"), "result": r, "elapsedMs": ms }));
                            ended.push(id);
                        }
                    }
                    other => {
                        if other == "RESULT" {
                            result = Some(data.clone());
                        }
                        if let Some((id, _)) = &cur {
                            let _ = app.emit(CHANNEL, json!({ "type": "line", "id": format!("verify:{id}"), "kind": other, "data": data }));
                        }
                    }
                });
                // Close out anything the batch did not reach (stopped, crashed or timed out).
                let reason = fallback_result(exit);
                for id in ids.iter().filter(|i| !ended.contains(i)) {
                    let was_running = cur.as_ref().map(|(c, _)| c == id).unwrap_or(false);
                    if !was_running {
                        let _ = app.emit(CHANNEL, json!({ "type": "start", "id": format!("verify:{id}"), "index": index, "total": total }));
                        index += 1;
                    }
                    let r = if was_running { reason.clone() } else { json!({ "status": "skipped", "summary": "Not reached" }) };
                    let _ = app.emit(CHANNEL, json!({ "type": "end", "id": format!("verify:{id}"), "result": r, "elapsedMs": 0 }));
                }
                clear_skip(&st);
            }
        }
    }
    if record_run {
        rec["finishedAt"] = json!(now_ms());
        rec["current"] = Value::Null;
        save_last_run(&rec);
    }
    let _ = app.emit(CHANNEL, json!({ "type": "done", "elapsedMs": started.elapsed().as_millis() as u64 }));
}

fn release_busy(app: &AppHandle) {
    use tauri::Manager;
    if let Some(s) = app.try_state::<AppState>() {
        s.busy.store(false, Ordering::SeqCst);
    }
}

/// `verify`: settings applied by earlier boosts, re-checked first in one fast batch.
/// `ids`: steps to run normally, in order.
#[tauri::command]
fn run_boost(app: AppHandle, state: State<'_, AppState>, ids: Vec<String>, verify: Option<Vec<String>>, options: Value) -> Result<(), String> {
    if state.busy.swap(true, Ordering::SeqCst) {
        return Err("A boost is already running".into());
    }
    let mut plan = Vec::new();
    if options["restorePoint"].as_bool().unwrap_or(true) {
        plan.push(PlanItem::One("restore-point".into()));
    }
    let verify: Vec<String> = verify.unwrap_or_default().into_iter().filter(|i| script_for(i).is_some()).collect();
    if !verify.is_empty() {
        plan.push(PlanItem::Verify(verify));
    }
    plan.extend(ids.into_iter().filter(|i| script_for(i).is_some()).map(PlanItem::One));
    let app2 = app.clone();
    thread::spawn(move || {
        run_plan(app2.clone(), plan, options, true);
        release_busy(&app2);
    });
    Ok(())
}

#[tauri::command]
fn revert_all(app: AppHandle, state: State<'_, AppState>) -> Result<(), String> {
    if state.busy.swap(true, Ordering::SeqCst) {
        return Err("Another operation is running".into());
    }
    let app2 = app.clone();
    thread::spawn(move || {
        run_plan(app2.clone(), vec![PlanItem::One("revert".into())], json!({}), false);
        // After an undo the next boost starts fresh.
        if !program_data().join("backup.json").exists() {
            let _ = std::fs::rename(last_run_path(), program_data().join(format!("last-run-undone-{}.json", now_ms())));
        }
        release_busy(&app2);
    });
    Ok(())
}

/// What earlier boosts did: per-step status and time, and whether the last run finished.
#[tauri::command]
fn last_run() -> Value {
    load_last_run()
}

/// Asks the running step to stop. Long steps stop cleanly and keep their partial
/// results; anything else is force-stopped after a few seconds.
#[tauri::command]
fn skip_step(state: State<'_, AppState>) -> Result<(), String> {
    if !state.busy.load(Ordering::SeqCst) {
        return Ok(());
    }
    let p = skip_flag_path();
    if let Some(dir) = p.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    std::fs::write(&p, b"1").map_err(|e| e.to_string())?;
    let mut g = state.skip_at.lock().map_err(|e| e.to_string())?;
    if g.is_none() {
        *g = Some(Instant::now());
    }
    Ok(())
}

#[tauri::command]
fn backup_count() -> usize {
    let p = program_data().join("backup.json");
    std::fs::read_to_string(p)
        .ok()
        .and_then(|s| serde_json::from_str::<Value>(s.trim_start_matches('\u{FEFF}')).ok())
        .map(|v| match v {
            Value::Array(a) => a.len(),
            Value::Object(_) => 1,
            _ => 0,
        })
        .unwrap_or(0)
}

/// Opens a URL, app, shortcut or protocol link un-elevated through the shell.
#[tauri::command]
fn open_target(target: String) -> Result<(), String> {
    if target.trim().is_empty() {
        return Ok(());
    }
    let mut c = Command::new(system_root().join("explorer.exe"));
    c.arg(&target);
    c.spawn().map(|_| ()).map_err(|e| e.to_string())
}

#[tauri::command]
fn restart_pc() -> Result<(), String> {
    let mut c = Command::new(system_root().join("System32").join("shutdown.exe"));
    c.args(["/r", "/t", "5", "/c", "OmniBoost: restarting to finish applying optimizations"]);
    hidden(&mut c);
    c.spawn().map(|_| ()).map_err(|e| e.to_string())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .manage(AppState::default())
        .invoke_handler(tauri::generate_handler![
            get_tweaks,
            scan,
            start_monitor,
            run_boost,
            revert_all,
            skip_step,
            last_run,
            backup_count,
            open_target,
            restart_pc
        ])
        .run(tauri::generate_context!())
        .expect("error while running OmniBoost");
}
