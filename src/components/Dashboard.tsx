import { motion } from "framer-motion";
import {
  Activity, Cpu, ExternalLink, Fan, Gamepad2, HardDrive, Lock, MemoryStick, Monitor, ShieldCheck,
  Thermometer, Undo2, Zap, CircleCheck, Play,
} from "lucide-react";
import type { LastRun, MonTick, Scan } from "../lib/types";
import { openTarget, timeAgo, TWEAKS } from "../lib/api";

const fade = (i: number) => ({ initial: { opacity: 0, y: 14 }, animate: { opacity: 1, y: 0 }, transition: { delay: 0.05 * i, duration: 0.45, ease: [0.2, 0.8, 0.2, 1] } });

function scoreColor(s: number) {
  if (s >= 85) return "#34d399";
  if (s >= 60) return "#4f8cff";
  if (s >= 40) return "#fbbf24";
  return "#fb5a73";
}

export function ScoreRing({ score }: { score: number }) {
  const r = 64;
  const c = 2 * Math.PI * r;
  const col = scoreColor(score);
  return (
    <div className="score">
      <svg width="150" height="150" viewBox="0 0 150 150">
        <defs>
          <linearGradient id="sg" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stopColor="#2ee6d6" />
            <stop offset="0.5" stopColor={col} />
            <stop offset="1" stopColor="#a35cff" />
          </linearGradient>
        </defs>
        <circle cx="75" cy="75" r={r} fill="none" stroke="rgba(255,255,255,0.07)" strokeWidth="11" />
        <motion.circle
          cx="75" cy="75" r={r} fill="none" stroke="url(#sg)" strokeWidth="11" strokeLinecap="round"
          strokeDasharray={c}
          initial={{ strokeDashoffset: c }}
          animate={{ strokeDashoffset: c * (1 - score / 100) }}
          transition={{ duration: 1.4, ease: [0.2, 0.8, 0.2, 1] }}
          style={{ filter: `drop-shadow(0 0 8px ${col}88)` }}
        />
      </svg>
      <div className="num">
        <div>
          <b style={{ color: col }}>{score}</b>
          <small>PC health</small>
        </div>
      </div>
    </div>
  );
}

function Spark({ data, color, max }: { data: number[]; color: string; max?: number }) {
  if (data.length < 2) return <svg className="spark" />;
  const hi = max ?? Math.max(...data, 1);
  const lo = max ? 0 : Math.min(...data);
  const span = Math.max(hi - lo, 1);
  const pts = data.map((v, i) => `${(i / (data.length - 1)) * 100},${28 - ((v - lo) / span) * 24}`).join(" ");
  const id = `g${color.replace("#", "")}`;
  return (
    <svg className="spark" viewBox="0 0 100 30" preserveAspectRatio="none">
      <defs>
        <linearGradient id={id} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={color} stopOpacity="0.35" />
          <stop offset="1" stopColor={color} stopOpacity="0" />
        </linearGradient>
      </defs>
      <polygon points={`0,30 ${pts} 100,30`} fill={`url(#${id})`} />
      <polyline points={pts} fill="none" stroke={color} strokeWidth="1.6" vectorEffect="non-scaling-stroke" />
    </svg>
  );
}

function tempColor(t?: number) {
  if (t == null) return "#8b93a7";
  if (t >= 85) return "#fb5a73";
  if (t >= 70) return "#fbbf24";
  return "#34d399";
}

export function LiveStats({ hist, scan }: { hist: MonTick[]; scan: Scan }) {
  const last = hist[hist.length - 1] ?? ({} as MonTick);
  const series = (k: keyof MonTick) => hist.map((h) => (h[k] as number) ?? 0).slice(-40);
  const hasGpu = last.gpuTemp != null || scan.temps.gpu != null;
  const tiles = [
    { k: "CPU load", icon: <Cpu size={13} />, v: last.cpuLoad, unit: "%", sub: `${scan.cpu.cores} cores · ${scan.cpu.threads} threads`, color: "#4f8cff", data: series("cpuLoad"), max: 100 },
    { k: "System temp", icon: <Thermometer size={13} />, v: last.cpuTemp ?? scan.temps.cpu ?? undefined, unit: "°C", sub: last.cpuTemp != null ? "ACPI thermal zone" : "Sensor not exposed", color: tempColor(last.cpuTemp), data: series("cpuTemp") },
    { k: "GPU temp", icon: <Thermometer size={13} />, v: last.gpuTemp ?? scan.temps.gpu ?? undefined, unit: "°C", sub: hasGpu ? `${last.gpuPower ?? "-"} W · fan ${last.gpuFan ?? "-"}%` : "NVIDIA only in v1", color: tempColor(last.gpuTemp), data: series("gpuTemp") },
    { k: "GPU load", icon: <Activity size={13} />, v: last.gpuLoad, unit: "%", sub: last.gpuClock ? `${last.gpuClock} MHz core` : "", color: "#a35cff", data: series("gpuLoad"), max: 100 },
    { k: "Memory", icon: <MemoryStick size={13} />, v: last.ramUsedGB, unit: ` / ${Math.round(scan.ram.totalGB)} GB`, sub: last.ramPct != null ? `${last.ramPct}% in use` : "", color: "#2ee6d6", data: series("ramPct"), max: 100 },
  ];
  return (
    <motion.div className="stats" {...fade(2)}>
      {tiles.map((t) => (
        <div className="stat" key={t.k}>
          <div className="k">{t.icon}{t.k}{t.k === "CPU load" && <span className="live-dot" style={{ marginLeft: "auto" }} />}</div>
          <div className="v" style={t.k.includes("temp") ? { color: t.color } : undefined}>
            {t.v != null ? t.v : "–"}<small>{t.v != null ? t.unit : ""}</small>
          </div>
          <div className="s">{t.sub}</div>
          <Spark data={t.data} color={t.color} max={t.max} />
        </div>
      ))}
    </motion.div>
  );
}

function stepTitle(id: string) {
  const plain = id.replace(/^verify:/, "");
  if (plain === "restore-point") return "System Restore point";
  return TWEAKS.find((t) => t.id === plain)?.title ?? plain;
}

export function Hero({ scan, onBoost, onResume, onUndo, backups, last }: { scan: Scan; onBoost: () => void; onResume: () => void; onUndo: () => void; backups: number; last: LastRun | null }) {
  const stopped = last && !last.synthetic && last.startedAt && !last.finishedAt;
  const crit = scan.issues.filter((i) => i.severity === "critical").length;
  const warn = scan.issues.filter((i) => i.severity === "warning").length;
  const gpu = scan.gpus[0];
  const disp = scan.displays.find((d) => d.primary) ?? scan.displays[0];
  return (
    <motion.div className="card hero" {...fade(0)}>
      <ScoreRing score={scan.score} />
      <div className="who">
        <div className="machine">{scan.machine.name}</div>
        <div className="sub">{scan.os.name} · build {scan.os.build}{scan.machine.board ? ` · ${scan.machine.board}` : ""}</div>
        <div className="spec">
          <span>CPU</span><span>{scan.cpu.name}</span>
          <span>GPU</span><span>{gpu ? `${gpu.name}${gpu.driver ? ` · driver ${gpu.driver}` : ""}` : "Integrated"}</span>
          <span>RAM</span><span>{scan.ram.totalGB} GB {scan.ram.type !== "Unknown" ? scan.ram.type : ""} · {scan.ram.modules.length} stick{scan.ram.modules.length === 1 ? "" : "s"}{scan.ram.modules[0] ? ` · ${scan.ram.modules[0].configured} MT/s` : ""}</span>
          <span>SCREEN</span><span>{disp ? `${disp.name} · ${disp.width}×${disp.height} @ ${disp.hz} Hz` : "–"}</span>
        </div>
        <div className="chips">
          {crit > 0 && <span className="chip"><span className="dot sev-critical" />{crit} critical</span>}
          {warn > 0 && <span className="chip"><span className="dot sev-warning" />{warn} warning{warn > 1 ? "s" : ""}</span>}
          <span className="chip"><span className="dot" style={{ background: "#4f8cff" }} />{scan.power.scheme} plan</span>
          <span className="chip"><span className="dot" style={{ background: "#a35cff" }} />{scan.startupCount} startup apps</span>
        </div>
      </div>
      <div className="boost-wrap">
        <button className="boost-btn" onClick={onBoost}>
          <Zap size={22} fill="currentColor" /><span>Boost my PC</span>
        </button>
        <div className="boost-caption">
          {!last ? `${TWEAKS.length} optimizations · fully reversible` : last.synthetic ? "Next Boost verifies your earlier changes" : stopped ? `Last Boost ${timeAgo(last.startedAt)}` : `Last Boost ${timeAgo(last.finishedAt)} · next one verifies it first`}
        </div>
        {stopped && (
          <div className="resume">
            <span className="note">{last!.current ? `Stopped at ${stepTitle(last!.current)}` : "Stopped before it finished"}</span>
            <button className="btn-resume" onClick={onResume}><Play size={13} fill="currentColor" />Resume where it stopped</button>
          </div>
        )}
        {backups > 0 && (
          <button className="link-btn" onClick={onUndo}><Undo2 size={13} />Undo all OmniBoost changes</button>
        )}
      </div>
    </motion.div>
  );
}

export function Issues({ scan }: { scan: Scan }) {
  const order = { critical: 0, warning: 1, info: 2 } as const;
  const list = [...scan.issues].sort((a, b) => order[a.severity] - order[b.severity]);
  return (
    <motion.div className="card" {...fade(3)}>
      <h3><ShieldCheck size={14} />Diagnostics<span className="count">{list.length} found</span></h3>
      {list.length === 0 ? (
        <div className="empty"><CircleCheck size={16} color="#34d399" />No hardware or configuration problems found.</div>
      ) : (
        <div className="issues">
          {list.map((i, n) => (
            <div className="issue" key={n}>
              <span className={`sev sev-${i.severity}`} />
              <div>
                <div className="t">{i.title}<span className="area">{i.area}</span></div>
                <div className="d">{i.detail}</div>
              </div>
              {i.open ? (
                <button className="btn-sm" onClick={() => openTarget(i.open!)}>{i.fix || "Open"}<ExternalLink size={12} /></button>
              ) : <span />}
            </div>
          ))}
        </div>
      )}
    </motion.div>
  );
}

export function Hardware({ scan }: { scan: Scan }) {
  const ram = scan.ram;
  const rated = Math.max(0, ...ram.modules.map((m) => m.ratedFromPart ?? 0));
  const cfg = ram.modules[0]?.configured ?? 0;
  return (
    <motion.div className="card" {...fade(1)}>
      <h3><Cpu size={14} />Hardware</h3>
      <div className="hw-row">
        <div className="label">
          <span>Memory · {ram.totalGB} GB {ram.type}</span>
          {ram.dualChannel === true && <span className="badge good">Dual channel</span>}
          {ram.dualChannel === false && <span className="badge crit">Single channel</span>}
        </div>
        <div className="slots">
          {ram.modules.map((m, i) => (
            <div className="slot filled" key={i}>
              <div className="ch">{m.channel ? `CH ${m.channel}` : m.slot}</div>
              <div className="cap">{m.capacityGB} GB</div>
              <div className="sp">{m.configured} MT/s</div>
            </div>
          ))}
        </div>
        {rated > 0 && cfg > 0 && cfg < rated * 0.92 && (
          <div className="line-item" style={{ marginTop: 6 }}>
            <span className="grow" style={{ color: "#fb5a73" }}>XMP/EXPO off: running {cfg} of {rated} MT/s</span>
          </div>
        )}
      </div>
      <div className="hw-row">
        <div className="label"><span>Displays</span></div>
        {scan.displays.map((d) => (
          <div className="line-item" key={d.device}>
            <Monitor size={14} color="#8b93a7" />
            <span className="grow">{d.name}</span>
            <span className="meta">{d.width}×{d.height}</span>
            {d.maxHz > d.hz ? <span className="badge warn">{d.hz} → {d.maxHz} Hz</span> : <span className="badge good">{d.hz} Hz</span>}
          </div>
        ))}
      </div>
      <div className="hw-row">
        <div className="label"><span>Drives</span></div>
        {scan.disks.map((d, i) => (
          <div className="line-item" key={i}>
            <HardDrive size={14} color="#8b93a7" />
            <span className="grow">{d.name}</span>
            <span className="meta">{d.bus} {d.media} · {d.sizeGB >= 1000 ? `${(d.sizeGB / 1024).toFixed(1)} TB` : `${d.sizeGB} GB`}{d.temp ? ` · ${d.temp}°C` : ""}</span>
            {d.wear != null && <div className="bar" title={`${d.wear}% wear`}><i style={{ width: `${Math.max(3, d.wear)}%` }} /></div>}
            <span className={`badge ${d.health === "Healthy" ? "good" : "crit"}`}>{d.health || "?"}</span>
          </div>
        ))}
      </div>
      <div className="hw-row soon">
        <div className="label"><span><Fan size={12} style={{ verticalAlign: -2, marginRight: 6 }} />Fan curves for your build</span><span className="lock"><Lock size={11} />Coming in v2</span></div>
        <div className="line-item"><span className="grow" style={{ color: "#8b93a7" }}>Airflow-aware fan profiles need a signed hardware driver and ship in the next major update.</span></div>
      </div>
    </motion.div>
  );
}

export function Games({ scan }: { scan: Scan }) {
  return (
    <motion.div className="card" {...fade(4)}>
      <h3><Gamepad2 size={14} />Your games<span className="count">{scan.games.length} detected</span></h3>
      {scan.games.length === 0 ? (
        <div className="empty">No Steam, Epic or Riot games found.</div>
      ) : (
        <div className="games">
          {scan.games.map((g) => (
            <span className="game" key={g.exe} title={g.exe}>
              <span className="src">{g.source}</span>
              {g.name}
              {g.playtimeMin > 0 && <span style={{ color: "#5b6377", fontWeight: 500 }}>{Math.round(g.playtimeMin / 60)}h</span>}
            </span>
          ))}
        </div>
      )}
    </motion.div>
  );
}
