import { AnimatePresence, motion } from "framer-motion";
import { Download, Minus, RefreshCw, Square, X } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import logo from "./logo.png";
import { BoostModal } from "./components/BoostModal";
import { Games, Hardware, Hero, Issues, LiveStats } from "./components/Dashboard";
import { backupCount, lastRun, onMonitor, scanSystem, windowAction } from "./lib/api";
import type { LastRun, MonTick, Scan } from "./lib/types";
import { appVersion, checkForUpdate, type PendingUpdate } from "./lib/updates";

function TitleBar({ version }: { version: string }) {
  return (
    <div className="titlebar" data-tauri-drag-region>
      <div className="brand" data-tauri-drag-region>
        <img src={logo} alt="" />
        OmniBoost
        {version && <span className="tag">v{version}</span>}
      </div>
      <div className="drag" data-tauri-drag-region />
      <button className="wc" onClick={() => windowAction("minimize")} aria-label="Minimize"><Minus size={16} /></button>
      <button className="wc" onClick={() => windowAction("maximize")} aria-label="Maximize"><Square size={13} /></button>
      <button className="wc close" onClick={() => windowAction("close")} aria-label="Close"><X size={17} /></button>
    </div>
  );
}

export default function App() {
  const [scan, setScan] = useState<Scan | null>(null);
  const [step, setStep] = useState("Starting");
  const [error, setError] = useState("");
  const [hist, setHist] = useState<MonTick[]>([]);
  const [modal, setModal] = useState<null | "boost" | "revert" | "resume">(null);
  const [last, setLast] = useState<LastRun | null>(null);
  const [backups, setBackups] = useState(0);
  const [rescanning, setRescanning] = useState(false);
  const started = useRef(false);
  const [version, setVersion] = useState("");
  const [update, setUpdate] = useState<PendingUpdate | null>(null);
  const [updatePct, setUpdatePct] = useState<number | null>(null);
  const [updateError, setUpdateError] = useState("");

  // Check for a new version on launch and every 6 hours.
  useEffect(() => {
    appVersion().then(setVersion).catch(() => {});
    const check = () => checkForUpdate().then((u) => u && setUpdate(u)).catch(() => {});
    check();
    const t = setInterval(check, 6 * 60 * 60 * 1000);
    return () => clearInterval(t);
  }, []);

  const installUpdate = async () => {
    if (!update) return;
    setUpdateError("");
    setUpdatePct(0);
    try {
      await update.install(setUpdatePct);
    } catch (e) {
      setUpdatePct(null);
      setUpdateError(String(e));
    }
  };

  const doScan = useCallback(async (quiet = false) => {
    if (quiet) setRescanning(true);
    else { setScan(null); setError(""); }
    try {
      const s = await scanSystem(setStep);
      setScan(s);
      setBackups(await backupCount());
      setLast(await lastRun().catch(() => null));
    } catch (e) {
      if (!quiet) setError(String(e));
    } finally {
      setRescanning(false);
    }
  }, []);

  useEffect(() => {
    if (started.current) return;
    started.current = true;
    doScan();
    let un: (() => void) | undefined;
    onMonitor((t) => setHist((h) => (h.length > 60 ? [...h.slice(-60), t] : [...h, t]))).then((u) => (un = u));
    return () => un?.();
  }, [doScan]);

  return (
    <div className="app">
      <TitleBar version={version} />
      {!scan ? (
        <div className="splash">
          <div className="inner">
            <div className="logo-ring"><img src={logo} alt="" /></div>
            <h1>{error ? "Scan failed" : "Scanning your PC"}</h1>
            {error ? (
              <>
                <p className="err">{error}</p>
                <button className="btn-ghost" onClick={() => doScan()}><RefreshCw size={15} />Try again</button>
              </>
            ) : (
              <AnimatePresence mode="wait">
                <motion.p key={step} initial={{ opacity: 0, y: 6 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -6 }} transition={{ duration: 0.2 }}>
                  {step}…
                </motion.p>
              </AnimatePresence>
            )}
          </div>
        </div>
      ) : (
        <div className="main">
          {update && (
            <div className="banner update">
              <Download size={18} />
              <div className="grow">
                <b>{updatePct === null ? `OmniBoost ${update.version} is available` : `Installing OmniBoost ${update.version}… ${updatePct}%`}</b>
                <span>{updateError ? `Update failed: ${updateError}` : updatePct === null ? "Your settings and undo history are kept." : "OmniBoost restarts by itself."}</span>
              </div>
              {updatePct === null && <button className="btn-sm" onClick={installUpdate}>Update now</button>}
            </div>
          )}
          <div className="grid">
            <div className="col">
              <Hero scan={scan} backups={backups} last={last} onBoost={() => setModal("boost")} onResume={() => setModal("resume")} onUndo={() => setModal("revert")} />
              <LiveStats hist={hist} scan={scan} />
              <Issues scan={scan} />
              <Games scan={scan} />
            </div>
            <div className="col">
              <Hardware scan={scan} />
              <motion.div className="card" initial={{ opacity: 0, y: 14 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.3 }}>
                <h3>Rescan<span className="count">{rescanning ? "scanning…" : ""}</span></h3>
                <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
                  <span style={{ color: "#8b93a7", fontSize: 13, flex: 1 }}>Run the hardware check again after changing BIOS settings, drivers or RAM slots.</span>
                  <button className="btn-sm" disabled={rescanning} onClick={() => doScan(true)}><RefreshCw size={13} className={rescanning ? "spin" : ""} />Rescan</button>
                </div>
              </motion.div>
            </div>
          </div>
        </div>
      )}
      <AnimatePresence>
        {modal && scan && (
          <BoostModal
            key={modal}
            mode={modal === "revert" ? "revert" : "boost"}
            autoStart={modal === "resume"}
            scan={scan}
            last={last}
            onClose={(changed) => {
              setModal(null);
              if (changed) doScan(true);
            }}
          />
        )}
      </AnimatePresence>
    </div>
  );
}
