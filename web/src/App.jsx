import { useCallback, useEffect, useMemo, useRef, useState } from "react";

const STATUS_LABELS = {
  online: "Online",
  launching: "Launching",
  stopping: "Stopping",
  stopped: "Stopped",
  errored: "Errored",
};

const INITIAL_FORM = {
  name: "",
  script: "",
  cwd: ".",
  interpreter: "",
  instances: "1",
  execMode: "",
  watch: false,
  autorestart: true,
  args: "",
  envPairs: "",
  watchPath: "",
  ignoreWatch: "",
  maxMemoryMb: "",
  maxRestarts: "15",
  minUptime: "1000",
  restartDelay: "100",
  expBackoffRestartDelay: "0",
  cronRestart: "",
  outFile: "",
  errorFile: "",
  maxLogSizeMb: "",
  killTimeout: "6000",
};

function normalizeText(value) {
  return String(value ?? "").toLocaleLowerCase("en-US");
}

function parseIntOr(value, fallback) {
  const parsed = Number.parseInt(String(value ?? "").trim(), 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function optionalString(value) {
  const trimmed = String(value ?? "").trim();
  return trimmed ? trimmed : undefined;
}

function splitLines(value) {
  return String(value ?? "")
    .split(/\r?\n|,/)
    .map((item) => item.trim())
    .filter(Boolean);
}

function bytesFromMb(value) {
  const num = Number(String(value ?? "").trim());
  return Number.isFinite(num) && num > 0 ? Math.round(num * 1024 * 1024) : 0;
}

function mbFromBytes(value) {
  const num = Number(value ?? 0);
  return Number.isFinite(num) && num > 0 ? String(Math.round(num / 1024 / 1024)) : "";
}

function fmtBytes(value) {
  const num = Number(value ?? 0);
  if (!Number.isFinite(num) || num <= 0) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  let size = num;
  let index = 0;
  while (size >= 1024 && index < units.length - 1) {
    size /= 1024;
    index += 1;
  }
  const digits = size >= 100 ? 0 : size >= 10 ? 1 : 2;
  return `${size.toFixed(digits)} ${units[index]}`;
}

function fmtPercent(value) {
  const num = Number(value ?? 0);
  if (!Number.isFinite(num)) return "0%";
  return `${num.toFixed(num >= 100 ? 0 : 1)}%`;
}

function fmtDateTime(value) {
  const num = Number(value ?? 0);
  if (!Number.isFinite(num) || num <= 0) return "—";
  return new Date(num).toLocaleString("en-US", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  });
}

function fmtAgo(value) {
  const num = Number(value ?? 0);
  if (!Number.isFinite(num) || num <= 0) return "—";
  const diff = Date.now() - num;
  if (diff < 1000) return "just now";
  const units = [
    ["d", 86400000],
    ["h", 3600000],
    ["min", 60000],
    ["sec", 1000],
  ];
  for (const [label, size] of units) {
    if (diff >= size) return `${Math.floor(diff / size)} ${label} ago`;
  }
  return "just now";
}

function fmtDuration(start, end = Date.now()) {
  const startMs = Number(start ?? 0);
  const endMs = Number(end ?? 0);
  if (!Number.isFinite(startMs) || startMs <= 0 || !Number.isFinite(endMs) || endMs < startMs) {
    return "—";
  }
  const totalSeconds = Math.floor((endMs - startMs) / 1000);
  const days = Math.floor(totalSeconds / 86400);
  const hours = Math.floor((totalSeconds % 86400) / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}h ${minutes}m`;
  if (minutes > 0) return `${minutes}m ${seconds}s`;
  return `${seconds}s`;
}

function runtimeLabel(process) {
  if (!process) return "—";
  if (process.status === "online" || process.status === "launching") {
    return fmtDuration(process.startedAt || process.createdAt);
  }
  return fmtAgo(process.stoppedAt || process.createdAt);
}

function sortProcesses(processes) {
  const rank = { online: 0, launching: 1, stopping: 2, errored: 3, stopped: 4 };
  return [...(processes || [])].sort((a, b) => {
    const diff = (rank[a.status] ?? 99) - (rank[b.status] ?? 99);
    if (diff !== 0) return diff;
    const nameDiff = String(a.name || "").localeCompare(String(b.name || ""), "en");
    if (nameDiff !== 0) return nameDiff;
    return Number(a.id || 0) - Number(b.id || 0);
  });
}

function baseNameFor(name, processes) {
  const value = typeof name === "string" ? name : name?.name || "";
  const match = value.match(/^(.*)-(\d+)$/);
  if (!match) return value;
  const candidate = match[1];
  const hasFamily = (processes || []).some(
    (item) => item.name === candidate || String(item.name || "").startsWith(`${candidate}-`),
  );
  return hasFamily ? candidate : value;
}

function statusClass(status) {
  return `badge-${status || "stopped"}`;
}

function statusText(status) {
  return STATUS_LABELS[status] || status || "Unknown";
}

function buildPath(points, key, width, height, padding) {
  const values = points
    .map((point) => Number(point?.[key]))
    .filter((value) => Number.isFinite(value));
  if (values.length < 2) return "";
  const min = Math.min(...values);
  const max = Math.max(...values);
  const range = Math.max(max - min, 1);
  return points
    .map((point, index) => {
      const x = padding + (index / Math.max(points.length - 1, 1)) * (width - padding * 2);
      const raw = Number(point?.[key] ?? min);
      const y = height - padding - ((raw - min) / range) * (height - padding * 2);
      return `${index === 0 ? "M" : "L"} ${x.toFixed(2)} ${y.toFixed(2)}`;
    })
    .join(" ");
}

function buildArea(points, key, width, height, padding) {
  const path = buildPath(points, key, width, height, padding);
  if (!path) return "";
  const bottom = height - padding;
  return `${path} L ${(width - padding).toFixed(2)} ${bottom.toFixed(2)} L ${padding.toFixed(2)} ${bottom.toFixed(2)} Z`;
}

function SparkChart({ points }) {
  const width = 640;
  const height = 220;
  const padding = 18;
  const rssPath = buildPath(points, "rss", width, height, padding);
  const rssArea = buildArea(points, "rss", width, height, padding);
  const heapPath = buildPath(points, "heapUsed", width, height, padding);

  return (
    <div className="chart-frame">
      <svg viewBox={`0 0 ${width} ${height}`} role="img" aria-label="process metrics chart">
        <defs>
          <linearGradient id="rssGradient" x1="0" x2="0" y1="0" y2="1">
            <stop offset="0%" stopColor="rgba(99, 215, 255, 0.28)" />
            <stop offset="100%" stopColor="rgba(99, 215, 255, 0.02)" />
          </linearGradient>
        </defs>
        <g opacity="0.22" stroke="rgba(255,255,255,0.12)">
          <line x1="0" y1="40" x2={width} y2="40" />
          <line x1="0" y1="110" x2={width} y2="110" />
          <line x1="0" y1="180" x2={width} y2="180" />
        </g>
        {rssArea ? <path d={rssArea} fill="url(#rssGradient)" /> : null}
        {rssPath ? (
          <path d={rssPath} fill="none" stroke="#63d7ff" strokeWidth="4" strokeLinecap="round" strokeLinejoin="round" />
        ) : null}
        {heapPath ? (
          <path
            d={heapPath}
            fill="none"
            stroke="#78f3c5"
            strokeWidth="3"
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeDasharray="5 6"
          />
        ) : null}
        {!rssPath && !heapPath ? (
          <text x="50%" y="50%" textAnchor="middle" dominantBaseline="middle" fill="rgba(236,247,255,0.55)">
            No socket metric stream yet
          </text>
        ) : null}
      </svg>
    </div>
  );
}

function SummaryCard({ label, value, note }) {
  return (
    <article className="summary-card">
      <span>{label}</span>
      <h3>{value}</h3>
      <p>{note}</p>
    </article>
  );
}

function App() {
  const [snapshot, setSnapshot] = useState({ timestamp: null, processes: [] });
  const [selectedId, setSelectedId] = useState(null);
  const [socketState, setSocketState] = useState("connecting");
  const [lastSocketMessageAt, setLastSocketMessageAt] = useState(null);
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("all");
  const [logLines, setLogLines] = useState(160);
  const [autoLogs, setAutoLogs] = useState(true);
  const [logs, setLogs] = useState({ text: "", updatedAt: null, loading: false });
  const [activity, setActivity] = useState([
    {
      id: Date.now(),
      type: "info",
      title: "Dashboard ready",
      description: "The React command center has started and is waiting for the live socket connection.",
      at: Date.now(),
    },
  ]);
  const [form, setForm] = useState(INITIAL_FORM);
  const [launcherOpen, setLauncherOpen] = useState(true);
  const reconnectTimer = useRef(null);
  const wsRef = useRef(null);
  const connectNoticeShown = useRef(false);

  const processes = useMemo(() => sortProcesses(snapshot.processes || []), [snapshot.processes]);

  const selectedProcess = useMemo(
    () => processes.find((item) => String(item.id) === String(selectedId)) || null,
    [processes, selectedId],
  );

  useEffect(() => {
    if (!processes.length) {
      setSelectedId(null);
      return;
    }
    if (!selectedId || !processes.some((item) => String(item.id) === String(selectedId))) {
      setSelectedId(processes[0].id);
    }
  }, [processes, selectedId]);

  const pushActivity = useCallback((type, title, description) => {
    setActivity((current) => [
      {
        id: Date.now() + Math.random(),
        type,
        title,
        description,
        at: Date.now(),
      },
      ...current,
    ].slice(0, 16));
  }, []);

  const pullSnapshot = useCallback(async (silent = false) => {
    try {
      const response = await fetch("/api/processes", { cache: "no-store" });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error || `HTTP ${response.status}`);
      setSnapshot({ timestamp: Date.now(), processes: payload.processes || [] });
      if (!silent) {
        pushActivity("success", "Fleet refreshed", "The latest process list was loaded through the HTTP fallback.");
      }
    } catch (error) {
      if (!silent) {
        pushActivity("error", "Failed to load fleet", error.message || "Unknown error");
      }
    }
  }, [pushActivity]);

  useEffect(() => {
    let cancelled = false;

    const connect = () => {
      if (cancelled) return;
      setSocketState((prev) => (prev === "connected" ? prev : "connecting"));
      const protocol = window.location.protocol === "https:" ? "wss" : "ws";
      const socket = new WebSocket(`${protocol}://${window.location.host}/ws`);
      wsRef.current = socket;

      socket.onopen = () => {
        if (cancelled) return;
        setSocketState("connected");
        if (!connectNoticeShown.current) {
          connectNoticeShown.current = true;
          pushActivity("success", "Live socket connected", "Real-time process updates are active.");
        }
      };

      socket.onmessage = (event) => {
        if (cancelled) return;
        try {
          const payload = JSON.parse(event.data);
          if (payload.type === "snapshot") {
            setSnapshot({ timestamp: payload.timestamp || Date.now(), processes: payload.processes || [] });
            setLastSocketMessageAt(Date.now());
          }
        } catch {
          // ignore bad frames
        }
      };

      socket.onerror = () => {
        socket.close();
      };

      socket.onclose = () => {
        if (cancelled) return;
        setSocketState("disconnected");
        clearTimeout(reconnectTimer.current);
        reconnectTimer.current = setTimeout(() => {
          pullSnapshot(true);
          connect();
        }, 1800);
      };
    };

    pullSnapshot(true);
    connect();

    return () => {
      cancelled = true;
      clearTimeout(reconnectTimer.current);
      if (wsRef.current) wsRef.current.close();
    };
  }, [pullSnapshot, pushActivity]);

  useEffect(() => {
    if (!selectedProcess) {
      setLogs({ text: "", updatedAt: null, loading: false });
      return;
    }

    let cancelled = false;
    let intervalId = null;

    const loadLogs = async (silent = false) => {
      setLogs((current) => ({ ...current, loading: !silent }));
      try {
        const response = await fetch(
          `/api/logs?id=${encodeURIComponent(selectedProcess.name)}&lines=${encodeURIComponent(logLines)}`,
          { cache: "no-store" },
        );
        const payload = await response.json();
        if (!response.ok) throw new Error(payload.error || `HTTP ${response.status}`);
        if (!cancelled) {
          setLogs({ text: payload.log || "", updatedAt: Date.now(), loading: false });
        }
      } catch (error) {
        if (!cancelled) {
          setLogs((current) => ({
            text: current.text || `Could not load logs: ${error.message || "unknown error"}`,
            updatedAt: current.updatedAt,
            loading: false,
          }));
        }
      }
    };

    loadLogs(true);
    if (autoLogs) {
      intervalId = window.setInterval(() => loadLogs(true), 2500);
    }

    return () => {
      cancelled = true;
      if (intervalId) window.clearInterval(intervalId);
    };
  }, [selectedProcess?.id, selectedProcess?.name, logLines, autoLogs]);

  const filteredProcesses = useMemo(() => {
    const query = normalizeText(search);
    return processes.filter((process) => {
      if (statusFilter !== "all" && process.status !== statusFilter) return false;
      if (!query) return true;
      const haystack = [process.name, process.script, process.cwd, baseNameFor(process, processes)]
        .map(normalizeText)
        .join(" ");
      return haystack.includes(query);
    });
  }, [processes, search, statusFilter]);

  const summary = useMemo(() => {
    const online = processes.filter((item) => item.status === "online").length;
    const alert = processes.filter(
      (item) => item.status === "errored" || item.status === "stopping" || Number(item.restarts || 0) >= 5,
    ).length;
    const groups = new Set(processes.map((item) => baseNameFor(item, processes))).size;
    const cpu = processes.reduce((sum, item) => sum + Number(item.summary?.cpuPercent || 0), 0);
    const rss = processes.reduce((sum, item) => sum + Number(item.summary?.rss || 0), 0);
    const watch = processes.filter((item) => item.watchEnabled).length;
    return {
      total: processes.length,
      online,
      alert,
      groups,
      cpu,
      rss,
      watch,
    };
  }, [processes]);

  const runAction = useCallback(async (action, payload = {}, options = {}) => {
    if (options.confirm && !window.confirm(options.confirm)) return false;
    try {
      pushActivity("info", `${action} sent`, payload.target || payload.name || "global action");
      const response = await fetch("/api/action", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action, ...payload }),
      });
      const result = await response.json();
      if (!response.ok || !result.success) {
        throw new Error(result.error || `HTTP ${response.status}`);
      }
      pushActivity("success", `${action} succeeded`, payload.target || payload.name || "Action completed");
      if (socketState !== "connected") {
        pullSnapshot(true);
      }
      return true;
    } catch (error) {
      pushActivity("error", `${action} failed`, error.message || "Unknown error");
      return false;
    }
  }, [pullSnapshot, pushActivity, socketState]);

  const handleGlobalAction = async (action) => {
    const confirmMap = {
      restart: "Restart all processes?",
      stop: "Stop all processes?",
      flush: "Flush all logs?",
    };
    await runAction(action, { target: "all" }, { confirm: confirmMap[action] });
  };

  const handleFormChange = (key, value) => {
    setForm((current) => ({ ...current, [key]: value }));
  };

  const fillFormFromProcess = (process) => {
    if (!process) return;
    const config = process.config || {};
    setForm({
      name: baseNameFor(process, processes) || process.name || "",
      script: process.script || "",
      cwd: process.cwd || ".",
      interpreter: config.interpreter || "",
      instances: String(
        processes.filter((item) => baseNameFor(item, processes) === baseNameFor(process, processes)).length || 1,
      ),
      execMode: config.execMode || "",
      watch: Boolean(process.watchEnabled || config.watch),
      autorestart: config.autorestart !== false,
      args: Array.isArray(config.args) ? config.args.join("\n") : "",
      envPairs: Array.isArray(config.envPairs) ? config.envPairs.join("\n") : "",
      watchPath: config.watchPath || "",
      ignoreWatch: Array.isArray(config.ignoreWatch) ? config.ignoreWatch.join("\n") : "",
      maxMemoryMb: mbFromBytes(config.maxMemoryRestart),
      maxRestarts: String(config.maxRestarts ?? 15),
      minUptime: String(config.minUptime ?? 1000),
      restartDelay: String(config.restartDelay ?? 100),
      expBackoffRestartDelay: String(config.expBackoffRestartDelay ?? 0),
      cronRestart: config.cronRestart || "",
      outFile: config.outFile || "",
      errorFile: config.errorFile || "",
      maxLogSizeMb: mbFromBytes(config.maxLogSize),
      killTimeout: String(config.killTimeout ?? 6000),
    });
    setLauncherOpen(true);
    pushActivity("info", "Launcher updated", `${process.name} configuration was copied into the form.`);
  };

  const handleStartSubmit = async (event) => {
    event.preventDefault();
    const payload = {
      name: optionalString(form.name),
      script: optionalString(form.script),
      cwd: optionalString(form.cwd) || ".",
      interpreter: optionalString(form.interpreter),
      args: splitLines(form.args),
      envPairs: splitLines(form.envPairs),
      instances: Math.max(1, parseIntOr(form.instances, 1)),
      watch: form.watch,
      watchPath: optionalString(form.watchPath),
      ignoreWatch: splitLines(form.ignoreWatch),
      maxMemoryRestart: bytesFromMb(form.maxMemoryMb),
      autorestart: form.autorestart,
      maxRestarts: parseIntOr(form.maxRestarts, 15),
      minUptime: parseIntOr(form.minUptime, 1000),
      restartDelay: parseIntOr(form.restartDelay, 100),
      outFile: optionalString(form.outFile),
      errorFile: optionalString(form.errorFile),
      execMode: optionalString(form.execMode),
      expBackoffRestartDelay: parseIntOr(form.expBackoffRestartDelay, 0),
      cronRestart: optionalString(form.cronRestart),
      maxLogSize: bytesFromMb(form.maxLogSizeMb),
      killTimeout: parseIntOr(form.killTimeout, 6000),
    };

    if (!payload.name || !payload.script) {
      pushActivity("error", "Missing form data", "Process name and script are required.");
      return;
    }

    const okay = await runAction("start", payload);
    if (okay) {
      setForm(INITIAL_FORM);
    }
  };

  const selectedMetrics = selectedProcess?.recentMetrics || [];
  const selectedCpu = Number(selectedProcess?.summary?.cpuPercent || 0);
  const selectedRss = Number(selectedProcess?.summary?.rss || 0);
  const selectedHeap = Number(selectedProcess?.summary?.heapUsed || 0);
  const selectedHeapTotal = Number(selectedProcess?.summary?.heapTotal || 0);
  const heapRatio = selectedHeapTotal > 0
    ? `${Math.round((selectedHeap / selectedHeapTotal) * 100)}% heap usage`
    : "Heap budget information is unavailable";

  return (
    <div className="app-shell">
      <header className="topbar surface">
        <div className="brand">
          <div className="brand-mark" aria-hidden="true" />
          <div>
            <p className="eyebrow">React Command Center</p>
            <h1>buncore realtime operations console</h1>
          </div>
        </div>

        <div className="topbar-controls">
          <span className={`socket-pill ${socketState}`}>
            {socketState === "connected"
              ? "Live Socket"
              : socketState === "connecting"
                ? "Connecting"
                : "Disconnected"}
          </span>
          <span className="micro-pill">
            son paket {lastSocketMessageAt ? fmtAgo(lastSocketMessageAt) : "waiting"}
          </span>
          <button className="btn ghost" onClick={() => pullSnapshot(false)}>HTTP yenile</button>
          <button className="btn" onClick={() => runAction("save")}>Kaydet</button>
          <button
            className="btn"
            onClick={() => runAction("resurrect", {}, { confirm: "Restore the saved fleet state?" })}
          >
            Restore
          </button>
          <button className="btn primary" onClick={() => setLauncherOpen((value) => !value)}>
            {launcherOpen ? "Hide launcher" : "New process"}
          </button>
        </div>
      </header>

      <section className="hero surface">
        <div className="hero-copy">
          <p className="eyebrow">Socket-first dashboard</p>
          <h2>A modern, rebuilt React command center with live operations.</h2>
          <p>
            This React web panel receives real-time fleet snapshots over WebSocket, manages processes with a modern card layout, and keeps the operational workflow on a single screen.
          </p>
          <div className="hero-actions">
            <button className="btn primary" onClick={() => handleGlobalAction("restart")}>Restart all</button>
            <button className="btn warn" onClick={() => handleGlobalAction("stop")}>Stop all</button>
            <button className="btn ghost" onClick={() => handleGlobalAction("flush")}>Flush logs</button>
          </div>
        </div>

        <div className="hero-side">
          <div className="hero-card">
            <div className="metric-inline">
              <span>Socket state</span>
              <strong>{socketState}</strong>
            </div>
            <div className="metric-inline">
              <span>Dashboard host</span>
              <strong>{window.location.origin}</strong>
            </div>
            <div className="metric-inline">
              <span>Selected process</span>
              <strong>{selectedProcess?.name || "—"}</strong>
            </div>
            <div className="metric-inline">
              <span>Latest snapshot</span>
              <strong>{snapshot.timestamp ? fmtDateTime(snapshot.timestamp) : "Waiting"}</strong>
            </div>
          </div>

          <div className="hero-card">
            <p className="eyebrow">Operational scope</p>
            <p>
              Restart, reload, stop, delete, flush, reset, signal, scale, and new process launch flows are built into the panel. Logs and process details are available on the same screen.
            </p>
          </div>
        </div>
      </section>

      <section className="summary-grid">
        <SummaryCard label="Total processes" value={summary.total} note="Total managed processes visible in the socket snapshot" />
        <SummaryCard label="Online" value={summary.online} note="Processes currently running" />
        <SummaryCard label="Alerts" value={summary.alert} note="Errored, stopping, or under restart pressure" />
        <SummaryCard label="Groups" value={summary.groups} note="Unique service groups by base name" />
        <SummaryCard label="Total CPU" value={fmtPercent(summary.cpu)} note="Overall fleet load" />
        <SummaryCard label="Total RSS" value={fmtBytes(summary.rss)} note="Total resident memory usage" />
        <SummaryCard label="Watch enabled" value={summary.watch} note="Processes with file watching enabled" />
      </section>

      <section className="workspace">
        <section className="panel">
          <div className="panel-head">
            <div>
              <p className="eyebrow">Fleet overview</p>
              <h2>Live socket fleet list</h2>
              <p>Control services from one place with search, filters, and quick action buttons.</p>
            </div>
            <div className="panel-actions">
              <span className="micro-pill">{filteredProcesses.length}/{processes.length} visible</span>
              <span className="micro-pill">last update {snapshot.timestamp ? fmtAgo(snapshot.timestamp) : "—"}</span>
            </div>
          </div>

          <div className="panel-body">
            <div className="filters">
              <input
                className="input"
                value={search}
                onChange={(event) => setSearch(event.target.value)}
                placeholder="Search by name, script, or cwd..."
              />
              <select className="select" value={statusFilter} onChange={(event) => setStatusFilter(event.target.value)}>
                <option value="all">All statuses</option>
                <option value="online">Online</option>
                <option value="launching">Launching</option>
                <option value="stopping">Stopping</option>
                <option value="stopped">Stopped</option>
                <option value="errored">Errored</option>
              </select>
              <button className="btn ghost" onClick={() => {
                setSearch("");
                setStatusFilter("all");
              }}>
                Clear filters
              </button>
            </div>

            {filteredProcesses.length ? (
              <div className="fleet-list">
                {filteredProcesses.map((process) => {
                  const cpu = Number(process.summary?.cpuPercent || 0);
                  const rss = Number(process.summary?.rss || 0);
                  const heap = Number(process.summary?.heapUsed || 0);
                  const heapTotal = Number(process.summary?.heapTotal || 0);
                  const heapStatus = heapTotal > 0 ? `${Math.round((heap / heapTotal) * 100)}% heap` : "heap data unavailable";
                  const selected = String(process.id) === String(selectedId);
                  const baseName = baseNameFor(process, processes);
                  const familyCount = processes.filter((item) => baseNameFor(item, processes) === baseName).length || 1;

                  return (
                    <article key={process.id} className={`process-card ${selected ? "selected" : ""}`}>
                      <div className="process-main">
                        <div className="process-title">
                          <span className={`status-dot status-${process.status}`} />
                          <button onClick={() => setSelectedId(process.id)}>
                            <h3>{process.name}</h3>
                            <div className="process-subtitle">ID {process.id} • PID {process.pid || "—"}</div>
                          </button>
                        </div>
                        <div className="process-script">{process.script || "No script information"}</div>
                        <div className="tag-row">
                          <span className={`status-pill ${statusClass(process.status)}`}>{statusText(process.status)}</span>
                          <span className="micro-pill">base {baseName}</span>
                          <span className="micro-pill">{familyCount} instance</span>
                          <span className="micro-pill">watch {process.watchEnabled ? "on" : "off"}</span>
                        </div>
                      </div>

                      <div className="metric-block">
                        <div className="metric-label">CPU</div>
                        <div className="metric-value">{fmtPercent(cpu)}</div>
                        <div className="metric-note">lag {Math.round(Number(process.summary?.runtimeLagMs || 0))} ms</div>
                        <div className="progress"><span style={{ width: `${Math.max(4, Math.min(cpu, 100))}%` }} /></div>
                      </div>

                      <div className="metric-block">
                        <div className="metric-label">Memory</div>
                        <div className="metric-value">{fmtBytes(rss)}</div>
                        <div className="metric-note">{heapStatus}</div>
                        <div className="progress"><span style={{ width: `${Math.max(4, Math.min((rss / 1024 / 1024 / 1024) * 100, 100))}%` }} /></div>
                      </div>

                      <div className="metric-block">
                        <div className="metric-label">Lifecycle</div>
                        <div className="metric-value">{runtimeLabel(process)}</div>
                        <div className="metric-note">{process.restarts || 0} restart</div>
                      </div>

                      <div className="metric-block">
                        <div className="metric-label">Runtime</div>
                        <div className="metric-value">{process.runtime || "generic"}</div>
                        <div className="metric-note">{process.platform || "unknown"}</div>
                      </div>

                      <div className="process-actions">
                        <div className="control-grid-actions">
                          <button className="btn small primary" onClick={() => runAction("restart", { target: process.name })}>Restart</button>
                          <button className="btn small" disabled={process.status !== "online"} onClick={() => runAction("reload", { target: process.name })}>Reload</button>
                          <button className="btn small warn" disabled={["stopped", "stopping"].includes(process.status)} onClick={() => runAction("stop", { target: process.name })}>Stop</button>
                          <button className="btn small danger" onClick={() => runAction("delete", { target: process.name }, { confirm: `Delete ${process.name}?` })}>Delete</button>
                        </div>
                      </div>
                    </article>
                  );
                })}
              </div>
            ) : (
              <div className="empty-state">
                <h3>No processes match the current filters</h3>
                <p>Clear the filters or launch a new process from the panel on the right.</p>
              </div>
            )}
          </div>
        </section>

        <aside className="panel-stack">
          <section className="panel">
            <div className="panel-head">
              <div>
                <p className="eyebrow">Inspector</p>
                <h2>Selected process</h2>
                <p>Real-time resource charts, logs, configuration, and management actions.</p>
              </div>
              <div className="panel-actions">
                <span className="micro-pill">{selectedProcess ? baseNameFor(selectedProcess, processes) : "No selection"}</span>
              </div>
            </div>

            <div className="panel-content">
              {selectedProcess ? (
                <div className="panel-grid">
                  <div className="detail-hero">
                    <div className="detail-top">
                      <div>
                        <p className="eyebrow">Selected process</p>
                        <h3>{selectedProcess.name}</h3>
                        <div className="detail-meta">
                          {selectedProcess.script}<br />
                          {selectedProcess.cwd}
                        </div>
                      </div>
                      <div className="panel-actions">
                        <span className={`status-pill ${statusClass(selectedProcess.status)}`}>{statusText(selectedProcess.status)}</span>
                        <span className="micro-pill">PID {selectedProcess.pid || "—"}</span>
                      </div>
                    </div>
                    <div className="panel-actions" style={{ marginTop: 16 }}>
                      <button className="btn small primary" onClick={() => runAction("restart", { target: selectedProcess.name })}>Restart</button>
                      <button className="btn small" disabled={selectedProcess.status !== "online"} onClick={() => runAction("reload", { target: selectedProcess.name })}>Reload</button>
                      <button className="btn small warn" disabled={["stopped", "stopping"].includes(selectedProcess.status)} onClick={() => runAction("stop", { target: selectedProcess.name })}>Stop</button>
                      <button className="btn small danger" onClick={() => runAction("delete", { target: selectedProcess.name }, { confirm: `Delete ?` })}>Delete</button>
                      <button className="btn small ghost" onClick={() => runAction("flush", { target: selectedProcess.name })}>Flush log</button>
                      <button className="btn small ghost" onClick={() => runAction("reset", { target: selectedProcess.name })}>Reset counters</button>
                      <button className="btn small ghost" onClick={() => fillFormFromProcess(selectedProcess)}>Copy to launcher</button>
                    </div>
                  </div>

                  <div className="stats-grid">
                    <article className="stat-card">
                      <span>CPU</span>
                      <h4>{fmtPercent(selectedCpu)}</h4>
                      <p>runtime lag {Math.round(Number(selectedProcess.summary?.runtimeLagMs || 0))} ms</p>
                    </article>
                    <article className="stat-card">
                      <span>RSS</span>
                      <h4>{fmtBytes(selectedRss)}</h4>
                      <p>resident memory footprint</p>
                    </article>
                    <article className="stat-card">
                      <span>Heap</span>
                      <h4>{fmtBytes(selectedHeap)}</h4>
                      <p>{heapRatio}</p>
                    </article>
                    <article className="stat-card">
                      <span>Lifecycle</span>
                      <h4>{runtimeLabel(selectedProcess)}</h4>
                      <p>{selectedProcess.restarts || 0} restart • {selectedProcess.unstableRestarts || 0} unstable</p>
                    </article>
                  </div>

                  <div className="subpanel">
                    <div className="subpanel-head">
                      <div>
                        <h3>Socket metric history</h3>
                        <p>{selectedMetrics.length ? `${selectedMetrics.length} data points streamed` : "No metric history yet"}</p>
                      </div>
                      <div className="panel-actions">
                        <span className="micro-pill">RSS</span>
                        <span className="micro-pill">Heap used</span>
                      </div>
                    </div>
                    <SparkChart points={selectedMetrics} />
                  </div>

                  <div className="subpanel">
                    <div className="subpanel-head">
                      <div>
                        <h3>Scale & signal</h3>
                        <p>Scale the selected service group and send signals to the active process.</p>
                      </div>
                    </div>
                    <div className="control-grid">
                      <div className="control-card">
                        <h4>Scale group</h4>
                        <div className="form-field">
                          <span>Target group</span>
                          <input className="input" value={baseNameFor(selectedProcess, processes)} readOnly />
                        </div>
                        <div className="form-field" style={{ marginTop: 10 }}>
                          <span>Desired instances</span>
                          <input
                            className="input"
                            type="number"
                            min="0"
                            defaultValue={processes.filter((item) => baseNameFor(item, processes) === baseNameFor(selectedProcess, processes)).length || 1}
                            onBlur={(event) => {
                              const count = Math.max(0, parseIntOr(event.target.value, 1));
                              runAction("scale", { target: baseNameFor(selectedProcess, processes), count });
                            }}
                          />
                        </div>
                        <p className="helper-text">The scale command is sent when the field loses focus.</p>
                      </div>

                      <div className="control-card">
                        <h4>Signal process</h4>
                        <div className="inline-actions">
                          {[
                            "SIGTERM",
                            "SIGINT",
                            "SIGHUP",
                            "SIGUSR1",
                            "SIGUSR2",
                          ].map((signal) => (
                            <button
                              key={signal}
                              className="btn small"
                              onClick={() => runAction("signal", { target: selectedProcess.name, signal })}
                            >
                              {signal}
                            </button>
                          ))}
                        </div>
                      </div>
                    </div>
                  </div>

                  <div className="subpanel">
                    <div className="subpanel-head">
                      <div>
                        <h3>Runtime & config</h3>
                        <p>Configuration and runtime details included in the socket snapshot.</p>
                      </div>
                    </div>
                    <div className="kv-grid">
                      <div className="kv-card"><div className="kv-label">Runtime</div><div className="kv-value">{selectedProcess.runtime || "generic"}</div></div>
                      <div className="kv-card"><div className="kv-label">Platform</div><div className="kv-value">{selectedProcess.platform || "unknown"}</div></div>
                      <div className="kv-card"><div className="kv-label">Created</div><div className="kv-value">{fmtDateTime(selectedProcess.createdAt)}</div></div>
                      <div className="kv-card"><div className="kv-label">Started</div><div className="kv-value">{fmtDateTime(selectedProcess.startedAt)}</div></div>
                      <div className="kv-card"><div className="kv-label">Stopped</div><div className="kv-value">{fmtDateTime(selectedProcess.stoppedAt)}</div></div>
                      <div className="kv-card"><div className="kv-label">Last exit code</div><div className="kv-value">{selectedProcess.lastExitCode ?? "—"}</div></div>
                      <div className="kv-card wide"><div className="kv-label">Script</div><div className="kv-value"><code>{selectedProcess.script}</code></div></div>
                      <div className="kv-card wide"><div className="kv-label">Working directory</div><div className="kv-value"><code>{selectedProcess.cwd}</code></div></div>
                      <div className="kv-card wide"><div className="kv-label">Args</div><div className="kv-value"><code>{(selectedProcess.config?.args || []).join("\n") || "—"}</code></div></div>
                      <div className="kv-card wide"><div className="kv-label">Environment</div><div className="kv-value"><code>{(selectedProcess.config?.envPairs || []).join("\n") || "—"}</code></div></div>
                      <div className="kv-card"><div className="kv-label">Watch</div><div className="kv-value">{selectedProcess.watchEnabled ? "enabled" : "disabled"}</div></div>
                      <div className="kv-card"><div className="kv-label">Watch path</div><div className="kv-value"><code>{selectedProcess.config?.watchPath || "—"}</code></div></div>
                      <div className="kv-card"><div className="kv-label">Exec mode</div><div className="kv-value">{selectedProcess.config?.execMode || "auto"}</div></div>
                      <div className="kv-card"><div className="kv-label">Interpreter</div><div className="kv-value">{selectedProcess.config?.interpreter || "auto"}</div></div>
                      <div className="kv-card"><div className="kv-label">Max memory restart</div><div className="kv-value">{selectedProcess.config?.maxMemoryRestart ? fmtBytes(selectedProcess.config.maxMemoryRestart) : "unlimited"}</div></div>
                      <div className="kv-card"><div className="kv-label">Kill timeout</div><div className="kv-value">{selectedProcess.config?.killTimeout || 6000} ms</div></div>
                      <div className="kv-card wide"><div className="kv-label">Combined log</div><div className="kv-value"><code>{selectedProcess.logPaths?.combined || "—"}</code></div></div>
                      <div className="kv-card wide"><div className="kv-label">Stdout log</div><div className="kv-value"><code>{selectedProcess.logPaths?.stdout || selectedProcess.config?.outFile || "—"}</code></div></div>
                      <div className="kv-card wide"><div className="kv-label">Stderr log</div><div className="kv-value"><code>{selectedProcess.logPaths?.stderr || selectedProcess.config?.errorFile || "—"}</code></div></div>
                    </div>
                  </div>

                  <div className="subpanel">
                    <div className="subpanel-head">
                      <div>
                        <h3>Logs</h3>
                        <p>{selectedProcess.logPaths?.combined || "combined logs"}</p>
                      </div>
                      <div className="log-actions">
                        <label className="toggle">
                          <input type="checkbox" checked={autoLogs} onChange={(event) => setAutoLogs(event.target.checked)} />
                          Auto log
                        </label>
                        <select className="select" style={{ width: 120 }} value={logLines} onChange={(event) => setLogLines(parseIntOr(event.target.value, 160))}>
                          <option value="80">80 lines</option>
                          <option value="160">160 lines</option>
                          <option value="320">320 lines</option>
                        </select>
                        <button className="btn small" onClick={() => navigator.clipboard?.writeText(logs.text || "")}>Copy</button>
                      </div>
                    </div>
                    <div className="log-box">
                      <pre>{logs.loading ? "loading logs..." : logs.text || "No logs have been loaded yet."}</pre>
                    </div>
                    <div className="log-meta">last log update {logs.updatedAt ? fmtDateTime(logs.updatedAt) : "—"}</div>
                  </div>
                </div>
              ) : (
                <div className="empty-state">
                  <h3>Select a process</h3>
                  <p>The right panel shows live metrics, configuration details, and control actions for the selected process.</p>
                </div>
              )}
            </div>
          </section>

          {launcherOpen ? (
            <section className="panel">
              <div className="panel-head">
                <div>
                  <p className="eyebrow">Launcher</p>
                  <h2>Start a new process</h2>
                  <p>Create a process from the React panel, define its configuration, set watch behavior, and add it to the fleet.</p>
                </div>
              </div>
              <form className="panel-form" onSubmit={handleStartSubmit}>
                <div className="launcher-card">
                  <div className="form-grid">
                    <label className="form-field">
                      <span>Process name</span>
                      <input className="input" value={form.name} onChange={(event) => handleFormChange("name", event.target.value)} placeholder="api" />
                    </label>
                    <label className="form-field">
                      <span>Script</span>
                      <input className="input" value={form.script} onChange={(event) => handleFormChange("script", event.target.value)} placeholder="server.ts" />
                    </label>
                    <label className="form-field">
                      <span>Working directory</span>
                      <input className="input" value={form.cwd} onChange={(event) => handleFormChange("cwd", event.target.value)} placeholder="." />
                    </label>
                    <label className="form-field">
                      <span>Interpreter</span>
                      <input className="input" value={form.interpreter} onChange={(event) => handleFormChange("interpreter", event.target.value)} placeholder="bun | node | deno" />
                    </label>
                    <label className="form-field">
                      <span>Instances</span>
                      <input className="input" type="number" min="1" value={form.instances} onChange={(event) => handleFormChange("instances", event.target.value)} />
                    </label>
                    <label className="form-field">
                      <span>Exec mode</span>
                      <select className="select" value={form.execMode} onChange={(event) => handleFormChange("execMode", event.target.value)}>
                        <option value="">Auto</option>
                        <option value="fork">fork</option>
                        <option value="cluster">cluster</option>
                      </select>
                    </label>
                    <label className="form-field-checkbox">
                      <span>Watch</span>
                      <input type="checkbox" checked={form.watch} onChange={(event) => handleFormChange("watch", event.target.checked)} />
                    </label>
                    <label className="form-field-checkbox">
                      <span>Autorestart</span>
                      <input type="checkbox" checked={form.autorestart} onChange={(event) => handleFormChange("autorestart", event.target.checked)} />
                    </label>
                    <label className="form-field full">
                      <span>Args</span>
                      <textarea className="textarea" value={form.args} onChange={(event) => handleFormChange("args", event.target.value)} placeholder="Write one argument per line" />
                    </label>
                    <label className="form-field full">
                      <span>Environment</span>
                      <textarea className="textarea" value={form.envPairs} onChange={(event) => handleFormChange("envPairs", event.target.value)} placeholder={`PORT=3000\nNODE_ENV=production`} />
                    </label>
                    <div className="form-card">
                      <h4>Watch & restart</h4>
                      <label className="form-field">
                        <span>Watch path</span>
                        <input className="input" value={form.watchPath} onChange={(event) => handleFormChange("watchPath", event.target.value)} placeholder="src" />
                      </label>
                      <label className="form-field">
                        <span>Ignore watch</span>
                        <textarea className="textarea" value={form.ignoreWatch} onChange={(event) => handleFormChange("ignoreWatch", event.target.value)} placeholder={`node_modules\ndist`} />
                      </label>
                      <label className="form-field">
                        <span>Max restarts</span>
                        <input className="input" type="number" min="0" value={form.maxRestarts} onChange={(event) => handleFormChange("maxRestarts", event.target.value)} />
                      </label>
                      <label className="form-field">
                        <span>Restart delay (ms)</span>
                        <input className="input" type="number" min="0" value={form.restartDelay} onChange={(event) => handleFormChange("restartDelay", event.target.value)} />
                      </label>
                    </div>
                    <div className="form-card">
                      <h4>Memory & logging</h4>
                      <label className="form-field">
                        <span>Max memory restart (MB)</span>
                        <input className="input" type="number" min="0" value={form.maxMemoryMb} onChange={(event) => handleFormChange("maxMemoryMb", event.target.value)} />
                      </label>
                      <label className="form-field">
                        <span>Max log size (MB)</span>
                        <input className="input" type="number" min="0" value={form.maxLogSizeMb} onChange={(event) => handleFormChange("maxLogSizeMb", event.target.value)} />
                      </label>
                      <label className="form-field">
                        <span>Stdout log path</span>
                        <input className="input" value={form.outFile} onChange={(event) => handleFormChange("outFile", event.target.value)} placeholder="logs/app.out.log" />
                      </label>
                      <label className="form-field">
                        <span>Stderr log path</span>
                        <input className="input" value={form.errorFile} onChange={(event) => handleFormChange("errorFile", event.target.value)} placeholder="logs/app.err.log" />
                      </label>
                    </div>
                    <div className="form-card full">
                      <h4>Advanced</h4>
                      <div className="form-grid">
                        <label className="form-field">
                          <span>Min uptime (ms)</span>
                          <input className="input" type="number" min="0" value={form.minUptime} onChange={(event) => handleFormChange("minUptime", event.target.value)} />
                        </label>
                        <label className="form-field">
                          <span>Exp backoff delay (ms)</span>
                          <input className="input" type="number" min="0" value={form.expBackoffRestartDelay} onChange={(event) => handleFormChange("expBackoffRestartDelay", event.target.value)} />
                        </label>
                        <label className="form-field">
                          <span>Cron restart</span>
                          <input className="input" value={form.cronRestart} onChange={(event) => handleFormChange("cronRestart", event.target.value)} placeholder="0 0 * * *" />
                        </label>
                        <label className="form-field">
                          <span>Kill timeout (ms)</span>
                          <input className="input" type="number" min="0" value={form.killTimeout} onChange={(event) => handleFormChange("killTimeout", event.target.value)} />
                        </label>
                      </div>
                    </div>
                  </div>
                  <div className="form-actions" style={{ marginTop: 14 }}>
                    <button className="btn primary" type="submit">Start process</button>
                    <button className="btn ghost" type="button" onClick={() => setForm(INITIAL_FORM)}>Clear form</button>
                  </div>
                </div>
              </form>
            </section>
          ) : null}

          <section className="panel">
            <div className="panel-head">
              <div>
                <p className="eyebrow">Activity feed</p>
                <h2>Panel activity</h2>
                <p>The latest socket, HTTP fallback, and action request events are listed here.</p>
              </div>
            </div>
            <div className="panel-feed">
              <div className="feed-list">
                {activity.map((item) => (
                  <article key={item.id} className="activity-item">
                    <span className={`activity-dot ${item.type}`} />
                    <div>
                      <strong>{item.title}</strong>
                      <p>{item.description}</p>
                    </div>
                    <span className="activity-time">{fmtAgo(item.at)}</span>
                  </article>
                ))}
              </div>
            </div>
          </section>
        </aside>
      </section>
    </div>
  );
}

export default App;
