import { AnimatePresence, motion } from "framer-motion";
import {
  AppWindow, Ban, Check, CircleAlert, CircleCheck, ExternalLink, Gamepad2, HardDrive, Info, Layers, MemoryStick,
  Monitor, Network, Power, RotateCcw, Sparkles, Trash2, TriangleAlert, Undo2, Wrench, X, Zap, ListChecks,
  SkipForward, ShieldCheck, History,
} from "lucide-react";
import { useEffect, useMemo, useRef, useState } from "react";
import { formatBytes, formatDuration, onBoostEvent, openTarget, restartPc, revertAll, runBoost, skipStep, stepTime, timeAgo, TWEAKS } from "../lib/api";
import type { BoostEvent, FeedItem, LastRun, ManualItem, Scan, StepResult, Tweak } from "../lib/types";

export const CATEGORIES: { id: string; title: string; icon: JSX.Element }[] = [
  { id: "cleanup", title: "Cleanup", icon: <Trash2 size={15} /> },
  { id: "power", title: "Power & CPU", icon: <Power size={15} /> },
  { id: "graphics", title: "Graphics", icon: <Layers size={15} /> },
  { id: "display", title: "Display", icon: <Monitor size={15} /> },
  { id: "gaming", title: "Gaming", icon: <Gamepad2 size={15} /> },
  { id: "memory", title: "Memory", icon: <MemoryStick size={15} /> },
  { id: "background", title: "Background apps", icon: <AppWindow size={15} /> },
  { id: "network", title: "Network & ping", icon: <Network size={15} /> },
  { id: "storage", title: "Storage", icon: <HardDrive size={15} /> },
  { id: "drivers", title: "Drivers", icon: <Wrench size={15} /> },
];

const EXTRA_TITLES: Record<string, string> = { "restore-point": "System Restore point", revert: "Undo all OmniBoost changes" };
const SLOW: Record<string, number> = { "drivers-oem": 180, "clean-components": 420, "clean-update": 20, "clean-disk": 120, "disk-optimize": 60, "disk-scan": 45, "game-priority": 15, "restore-point": 30 };
const WEEK = 7 * 24 * 3600 * 1000;

type StepState = { id: string; title: string; status: "pending" | "active" | "done" | "skipped" | "failed" | "manual"; ms?: number; summary?: string };

function applicable(t: Tweak, scan: Scan) {
  if (t.needs === "nvidia") return scan.vendors.nvidia;
  if (t.needs === "amd") return scan.vendors.amd;
  if (t.needs === "discord") return scan.apps.discord;
  return true;
}

function StatusIcon({ s }: { s: StepState["status"] }) {
  if (s === "active") return <span className="si"><span className="spinner" /></span>;
  if (s === "done") return <span className="si" style={{ background: "rgba(52,211,153,.14)", color: "#34d399" }}><Check size={12} strokeWidth={3} /></span>;
  if (s === "failed") return <span className="si" style={{ background: "rgba(251,90,115,.14)", color: "#fb5a73" }}><X size={12} strokeWidth={3} /></span>;
  if (s === "manual") return <span className="si" style={{ background: "rgba(251,191,36,.14)", color: "#fbbf24" }}><ListChecks size={12} strokeWidth={2.5} /></span>;
  if (s === "skipped") return <span className="si" style={{ color: "#5b6377" }}><Ban size={13} /></span>;
  return <span className="si pending" />;
}

/** How the last boost left each step, for the plan and for resuming. */
function history(last: LastRun | null) {
  const prevDone = (id: string) => {
    const st = last?.steps?.[id]?.status;
    return st === "done" || st === "manual";
  };
  const planned = new Set((last?.planned ?? []).map((id) => id.replace(/^verify:/, "")));
  const unfinished = (id: string) => planned.has(id) && !prevDone(id);
  const recent = (id: string) => {
    const t = stepTime(last?.steps?.[id]);
    return t != null && Date.now() - t < WEEK;
  };
  return { prevDone, unfinished, recent };
}

function defaultSelection(available: Tweak[], last: LastRun | null) {
  if (!last) return new Set(available.filter((t) => t.default).map((t) => t.id));
  const h = history(last);
  return new Set(
    available
      .filter((t) => {
        if (h.unfinished(t.id)) return true;
        if (t.repeat === "verify") return h.prevDone(t.id) || t.default;
        if (t.repeat === "once") return h.prevDone(t.id) && h.recent(t.id) ? false : t.default;
        return t.default;
      })
      .map((t) => t.id),
  );
}

export function BoostModal({ mode, scan, last, autoStart, onClose }: { mode: "boost" | "revert"; scan: Scan; last: LastRun | null; autoStart?: boolean; onClose: (changed: boolean) => void }) {
  const available = useMemo(() => TWEAKS.filter((t) => applicable(t, scan)), [scan]);
  const hist = useMemo(() => history(last), [last]);
  const [stage, setStage] = useState<"plan" | "running" | "done">(mode === "revert" ? "running" : "plan");
  const [selected, setSelected] = useState<Set<string>>(() => defaultSelection(available, last));
  const [restorePoint, setRestorePoint] = useState(!last);
  const [stepPct, setStepPct] = useState<number | null>(null);
  const [stepStart, setStepStart] = useState(Date.now());
  const [skipping, setSkipping] = useState(false);
  const [verified, setVerified] = useState(0);
  const [repaired, setRepaired] = useState(0);
  const [closeApps, setCloseApps] = useState(true);
  const [steps, setSteps] = useState<StepState[]>([]);
  const [feed, setFeed] = useState<FeedItem[]>([]);
  const [msg, setMsg] = useState("");
  const [changes, setChanges] = useState(0);
  const [freed, setFreed] = useState(0);
  const [manual, setManual] = useState<ManualItem[]>([]);
  const [reboot, setReboot] = useState(false);
  const [startedAt, setStartedAt] = useState(0);
  const [now, setNow] = useState(Date.now());
  const [totalMs, setTotalMs] = useState(0);
  const [showLog, setShowLog] = useState(false);
  const [error, setError] = useState("");
  const feedRef = useRef<HTMLDivElement>(null);
  const stepsRef = useRef<HTMLDivElement>(null);
  const stick = useRef(true);
  const keyRef = useRef(0);
  const curId = useRef("");

  const titleOf = (id: string): string => {
    if (id.startsWith("verify:")) return `Verify: ${titleOf(id.slice(7))}`;
    return EXTRA_TITLES[id] ?? TWEAKS.find((t) => t.id === id)?.title ?? id;
  };

  // event stream
  useEffect(() => {
    let un: (() => void) | undefined;
    let dead = false;
    onBoostEvent((e: BoostEvent) => {
      if (e.type === "start") {
        curId.current = e.id;
        setMsg("");
        setStepPct(null);
        setStepStart(Date.now());
        setSkipping(false);
        setSteps((s) => s.map((x) => (x.id === e.id ? { ...x, status: "active" } : x)));
        setFeed((f) => [...f, { key: ++keyRef.current, id: e.id, kind: "INFO", msg: titleOf(e.id), target: "__section" }]);
      } else if (e.type === "line") {
        const d = e.data as Record<string, string>;
        if (e.kind === "STEP") {
          setMsg(d.msg ?? "");
          const p = (e.data as { pct?: unknown }).pct;
          if (typeof p === "number") setStepPct(p);
          return;
        }
        if (e.kind === "RESULT") return;
        if (e.kind === "CHANGE") {
          setChanges((c) => c + 1);
          if (e.id.startsWith("verify:")) setRepaired((r) => r + 1);
        }
        if (e.kind === "SAME" && e.id.startsWith("verify:")) setVerified((v) => v + 1);
        setFeed((f) => {
          const next = [...f, { key: ++keyRef.current, id: e.id, kind: e.kind, target: d.target, before: d.before, after: d.after, value: d.value, msg: d.msg, path: d.path }];
          return next.length > 2000 ? next.slice(-2000) : next;
        });
      } else if (e.type === "end") {
        const r = e.result as StepResult;
        const status = (["done", "skipped", "failed", "manual"].includes(r.status) ? r.status : "done") as StepState["status"];
        setSteps((s) => s.map((x) => (x.id === e.id ? { ...x, status, ms: e.elapsedMs, summary: r.summary } : x)));
        setStepPct(null);
        setSkipping(false);
        if (r.freedBytes) setFreed((f) => f + Number(r.freedBytes));
        if (r.reboot) setReboot(true);
        if (r.manual && r.manual.length) setManual((m) => [...m, ...r.manual!]);
      } else if (e.type === "done") {
        setTotalMs(e.elapsedMs);
        setStage("done");
      }
    }).then((u) => {
      if (dead) u();
      else un = u;
    });
    return () => {
      dead = true;
      un?.();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // revert starts immediately
  useEffect(() => {
    if (mode !== "revert") return;
    setSteps([{ id: "revert", title: titleOf("revert"), status: "pending" }]);
    setStartedAt(Date.now());
    const t = setTimeout(() => revertAll()?.catch?.((e: unknown) => setError(String(e))), 150);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (stage !== "running") return;
    const t = setInterval(() => setNow(Date.now()), 500);
    return () => clearInterval(t);
  }, [stage]);

  useEffect(() => {
    const el = feedRef.current;
    if (el && stick.current) el.scrollTop = el.scrollHeight;
  }, [feed]);

  useEffect(() => {
    const el = stepsRef.current?.querySelector(".stp.active") as HTMLElement | null;
    el?.scrollIntoView({ block: "nearest", behavior: "smooth" });
  }, [steps]);

  // Settings applied by an earlier boost are re-checked first in one fast batch; everything else runs as usual.
  const plan = useMemo(() => {
    const chosen = available.filter((t) => selected.has(t.id));
    const verify = chosen.filter((t) => last && t.repeat === "verify" && hist.prevDone(t.id)).map((t) => t.id);
    const run = chosen.filter((t) => !verify.includes(t.id)).map((t) => t.id);
    return { verify, run };
  }, [available, selected, last, hist]);

  const start = async () => {
    const seq = [...(restorePoint ? ["restore-point"] : []), ...plan.verify.map((id) => `verify:${id}`), ...plan.run];
    setSteps(seq.map((id) => ({ id, title: titleOf(id), status: "pending" })));
    setStartedAt(Date.now());
    setStage("running");
    try {
      await runBoost(plan.run, plan.verify, { restorePoint, closeApps });
    } catch (e) {
      setError(String(e));
      setStage("plan");
    }
  };

  // Resume: start straight away with the plan built from the last run.
  const autoStarted = useRef(false);
  useEffect(() => {
    if (!autoStart || mode !== "boost") return;
    const t = setTimeout(() => {
      if (autoStarted.current) return;
      autoStarted.current = true;
      start();
    }, 200);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const skip = async () => {
    setSkipping(true);
    try { await skipStep(); } catch { setSkipping(false); }
  };

  const toggle = (id: string) => setSelected((s) => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n; });
  const toggleCat = (cat: string, on: boolean) => setSelected((s) => {
    const n = new Set(s);
    available.filter((t) => t.category === cat).forEach((t) => (on ? n.add(t.id) : n.delete(t.id)));
    return n;
  });

  const finished = steps.filter((s) => !["pending", "active"].includes(s.status)).length;
  const active = steps.find((s) => s.status === "active");
  const frac = active && stepPct != null ? stepPct / 100 : 0;
  const pct = steps.length ? Math.min(100, Math.floor(((finished + frac) / steps.length) * 100)) : 0;
  const canSkip = !!active && (active.id === "restore-point" || !!TWEAKS.find((t) => t.id === active.id)?.skippable);
  const estSec = plan.run.reduce((a, id) => a + (SLOW[id] ?? 4), (restorePoint ? SLOW["restore-point"] : 0) + plan.verify.length * 1);
  const lastDone = last ? Object.values(last.steps ?? {}).filter((x) => x.status === "done" || x.status === "manual").length : 0;
  const lastUnfinished = !!(last && !last.synthetic && last.startedAt && !last.finishedAt);
  const lastStopped = lastUnfinished ? last?.current ?? null : null;
  const running = stage === "running";

  const close = () => { if (!running) onClose(stage === "done"); };

  return (
    <motion.div className="backdrop" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}>
      <motion.div
        className="modal"
        initial={{ opacity: 0, scale: 0.94, y: 18 }}
        animate={{ opacity: 1, scale: 1, y: 0 }}
        exit={{ opacity: 0, scale: 0.96, y: 10 }}
        transition={{ type: "spring", stiffness: 260, damping: 26 }}
      >
        {stage === "plan" && (
          <>
            <div className="m-head">
              <div>
                <h2>Your Boost plan</h2>
                <p>Built for {scan.cpu.name.replace(/\s+\d+-Core Processor/i, "")}{scan.gpus[0] ? ` + ${scan.gpus[0].name}` : ""}. Every change is saved so you can undo it in one click.</p>
              </div>
              <button className="x" onClick={close}><X size={18} /></button>
            </div>
            <div className="m-body">
              {last && (
                <div className="lastrun">
                  <span className="lr-ico"><History size={16} /></span>
                  <div className="grow">
                    <b>
                      {last.synthetic
                        ? `Found ${lastDone} settings from an earlier boost`
                        : lastStopped
                          ? `Last Boost stopped at ${titleOf(lastStopped.replace(/^verify:/, ""))}`
                          : lastUnfinished
                            ? "Last Boost did not finish"
                            : `Last Boost ${timeAgo(last.finishedAt)}`}
                    </b>
                    <span>
                      {plan.verify.length > 0 ? `${plan.verify.length} applied settings are re-checked first in one fast pass. ` : ""}
                      OmniBoost then continues with {plan.run.length} step{plan.run.length === 1 ? "" : "s"}. Steps finished in the last 7 days are off.
                    </span>
                  </div>
                </div>
              )}
              <div className="plan">
                {CATEGORIES.map((c) => {
                  const items = available.filter((t) => t.category === c.id);
                  if (!items.length) return null;
                  const on = items.filter((t) => selected.has(t.id)).length;
                  return (
                    <div className="cat" key={c.id}>
                      <div className="cat-head">
                        <span className="ico">{c.icon}</span>
                        <b>{c.title}</b>
                        <span className="n">{on}/{items.length}</span>
                        <span className={`switch ${on === items.length ? "on" : ""}`} onClick={() => toggleCat(c.id, on !== items.length)} />
                      </div>
                      {items.map((t) => (
                        <div className="tw" key={t.id} onClick={() => toggle(t.id)}>
                          <div>
                            <div className="tt">
                              {t.title}
                              {t.reboot && <span className="pill">restart</span>}
                              {t.warn && <span className="pill warn">security trade-off</span>}
                              {last && plan.verify.includes(t.id) && <span className="pill blue">verify</span>}
                              {last && hist.unfinished(t.id) && <span className="pill warn">not finished last time</span>}
                              {last && !hist.unfinished(t.id) && t.repeat === "once" && hist.prevDone(t.id) && <span className="pill good">done {timeAgo(stepTime(last.steps[t.id]))}</span>}
                            </div>
                            <div className="dd">{t.desc}</div>
                          </div>
                          <span className={`switch ${selected.has(t.id) ? "on" : ""}`} />
                        </div>
                      ))}
                    </div>
                  );
                })}
              </div>
            </div>
            <div className="m-foot">
              <span className={`check ${restorePoint ? "on" : ""}`} onClick={() => setRestorePoint(!restorePoint)}>
                <span className="box">{restorePoint && <Check size={12} strokeWidth={3} />}</span>Create a System Restore point first
              </span>
              <span className={`check ${closeApps ? "on" : ""}`} onClick={() => setCloseApps(!closeApps)}>
                <span className="box">{closeApps && <Check size={12} strokeWidth={3} />}</span>Allow closing Discord to apply settings
              </span>
              <span className="spacer" />
              {error && <span style={{ color: "#fb5a73", fontSize: 12 }}>{error}</span>}
              <span style={{ color: "#8b93a7", fontSize: 12.5 }}>About {Math.max(1, Math.round(estSec / 60))} min</span>
              <button className="btn-primary" disabled={selected.size === 0} onClick={start}>
                <Zap size={17} fill="currentColor" />{last ? "Verify and continue" : "Start Boost"} ({selected.size})
              </button>
            </div>
          </>
        )}

        {stage !== "plan" && (
          <>
            <div className="m-head">
              <div>
                <h2>{stage === "done" ? (mode === "revert" ? "Everything is back to how it was" : "Boost complete") : mode === "revert" ? "Undoing changes" : "Boosting your PC"}</h2>
                <p>{stage === "done" ? `Finished in ${formatDuration(totalMs)}` : "Watch every change as it happens. Keep OmniBoost open until it finishes."}</p>
              </div>
              {stage === "done" && <button className="x" onClick={close}><X size={18} /></button>}
            </div>

            {stage === "running" || showLog ? (
              <div className="m-body" style={{ padding: 0 }}>
                <div className="run">
                  <div className="run-left">
                    <div className="progress-head">
                      <div className="pct">{pct}%</div>
                      <div className="of">{finished} of {steps.length} steps · {formatDuration((stage === "done" ? startedAt + totalMs : now) - startedAt)}</div>
                      <div className="pbar"><i style={{ width: `${pct}%` }} /></div>
                    </div>
                    <div className="steps" ref={stepsRef}>
                      {steps.map((s) => (
                        <div key={s.id} className={`stp ${s.status}`} title={s.summary}>
                          <StatusIcon s={s.status} />
                          <span style={{ whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{s.title}</span>
                          <span className="ms">{s.ms != null ? formatDuration(s.ms) : s.status === "active" ? formatDuration(now - stepStart) : ""}</span>
                        </div>
                      ))}
                    </div>
                  </div>
                  <div className="run-right">
                    <div className="now">
                      <div className="what">
                        <b>
                          {stage === "done" ? "Change log" : active ? active.title : "Starting…"}
                          {stage === "running" && active && <em className="elapsed">{formatDuration(now - stepStart)}</em>}
                        </b>
                        <span>{stage === "done" ? `${feed.filter((f) => f.kind === "CHANGE").length} changes recorded in the undo journal` : msg || " "}</span>
                      </div>
                      <div className="counters">
                        <div className="counter"><b>{changes}</b><small>Changes</small></div>
                        {verified > 0 && <div className="counter"><b>{verified}</b><small>Verified</small></div>}
                        <div className="counter"><b>{formatBytes(freed)}</b><small>Freed</small></div>
                      </div>
                    </div>
                    <div
                      className="feed"
                      ref={feedRef}
                      onScroll={(e) => {
                        const el = e.currentTarget;
                        stick.current = el.scrollHeight - el.scrollTop - el.clientHeight < 60;
                      }}
                    >
                      <AnimatePresence initial={false}>
                        {feed.map((f) => <FeedRow key={f.key} f={f} />)}
                      </AnimatePresence>
                      {error && <div className="fi warn"><TriangleAlert size={14} /><div>{error}</div></div>}
                    </div>
                  </div>
                </div>
              </div>
            ) : (
              <div className="m-body">
                <div className="done-wrap">
                  <div className="done-hero">
                    <motion.div className="ok" initial={{ scale: 0.4, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} transition={{ type: "spring", stiffness: 300, damping: 16 }}>
                      <Check size={32} strokeWidth={3} />
                    </motion.div>
                    <div>
                      <h2>{mode === "revert" ? "All changes undone" : `${changes} optimizations applied`}</h2>
                      <p>
                        {mode === "revert"
                          ? "Your previous settings are restored."
                          : plan.verify.length > 0
                            ? repaired > 0
                              ? `${verified} settings from your last Boost are still in place. ${repaired} had been changed back and were fixed.`
                              : `All ${verified} settings from your last Boost are still in place.`
                            : "Your settings are saved in the undo journal. Run a game and feel the difference."}
                      </p>
                    </div>
                  </div>
                  <div className="tiles">
                    <div className="tile"><b>{changes}</b><small>Changes applied</small></div>
                    <div className="tile"><b>{formatBytes(freed)}</b><small>Disk space freed</small></div>
                    {plan.verify.length > 0 ? (
                      <div className="tile"><b>{verified}</b><small><ShieldCheck size={12} style={{ verticalAlign: -2, marginRight: 4 }} />Verified in place</small></div>
                    ) : (
                      <div className="tile"><b>{steps.filter((s) => s.status === "done").length}/{steps.length}</b><small>Steps completed</small></div>
                    )}
                    <div className="tile"><b>{formatDuration(totalMs)}</b><small>Total time</small></div>
                  </div>
                  {reboot && (
                    <div className="banner">
                      <RotateCcw size={20} color="#fbbf24" />
                      <div className="grow"><b>Restart to finish</b><span>GPU scheduling, scheduler, network and driver changes apply after a restart.</span></div>
                      <button className="btn-primary" style={{ height: 38 }} onClick={() => restartPc()}>Restart now</button>
                    </div>
                  )}
                  {manual.length > 0 && (
                    <>
                      <div className="sub-h">Finish these in 30 seconds</div>
                      <div className="manual">
                        {manual.map((m, i) => (
                          <div className="mi" key={i}>
                            <span className="n">{i + 1}</span>
                            <div><b>{m.title}</b><p>{m.detail}</p></div>
                            {m.open ? <button className="btn-sm" onClick={() => openTarget(m.open!)}>Open<ExternalLink size={12} /></button> : <span />}
                          </div>
                        ))}
                      </div>
                    </>
                  )}
                  <div className="sub-h">What OmniBoost did</div>
                  <div className="summary-list">
                    {steps.map((s) => (
                      <div className="sl" key={s.id}>
                        <StatusIcon s={s.status} />
                        <span className="grow">{s.title}</span>
                        <span className="meta" title={s.summary}>{s.summary}</span>
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            )}

            <div className="m-foot">
              {stage === "running" ? (
                <>
                  <span className="spinner" />
                  <span style={{ color: "#8b93a7", fontSize: 13 }}>
                    {canSkip ? "This step can take a few minutes. Skipping keeps what it already did." : "Working. Keep OmniBoost open until it finishes."}
                  </span>
                  <span className="spacer" />
                  {canSkip && (
                    <button className="btn-ghost" disabled={skipping} onClick={skip}>
                      <SkipForward size={15} />{skipping ? "Stopping…" : "Skip this step"}
                    </button>
                  )}
                </>
              ) : (
                <>
                  <button className="btn-ghost" onClick={() => setShowLog(!showLog)}>
                    <Sparkles size={15} />{showLog ? "Show summary" : "Show full change log"}
                  </button>
                  <span className="spacer" />
                  <button className="btn-primary" onClick={close}><CircleCheck size={17} />Done</button>
                </>
              )}
            </div>
          </>
        )}
      </motion.div>
    </motion.div>
  );
}

function FeedRow({ f }: { f: FeedItem }) {
  const anim = { initial: { opacity: 0, x: 18 }, animate: { opacity: 1, x: 0 }, transition: { duration: 0.25 } };
  if (f.target === "__section") return <motion.div className="fi section" {...anim}>{f.msg}</motion.div>;
  if (f.kind === "CHANGE")
    return (
      <motion.div className="fi change" {...anim}>
        <span className="ic"><CircleCheck size={15} color="#34d399" /></span>
        <div>
          <div className="tg">{f.target}</div>
          <div className="ba"><span className="b">{f.before}</span><span style={{ color: "#5b6377" }}>→</span><span className="a">{f.after}</span></div>
          {f.path && <div className="path">{f.path}</div>}
        </div>
      </motion.div>
    );
  if (f.kind === "SAME")
    return (
      <motion.div className="fi same" {...anim}>
        <span className="ic"><Check size={14} /></span>
        <div><span className="tg">{f.target}</span> <span style={{ marginLeft: 6 }}>{f.value}</span><span style={{ marginLeft: 8, fontSize: 11 }}>{f.id.startsWith("verify:") ? "verified" : "already optimal"}</span></div>
      </motion.div>
    );
  if (f.kind === "WARN" || f.kind === "STDERR")
    return (
      <motion.div className="fi warn" {...anim}>
        <span className="ic"><CircleAlert size={14} /></span>
        <div>{f.msg}</div>
      </motion.div>
    );
  return (
    <motion.div className="fi info" {...anim}>
      <span className="ic"><Info size={14} /></span>
      <div>{f.msg}</div>
    </motion.div>
  );
}

export function UndoIcon() {
  return <Undo2 size={14} />;
}
