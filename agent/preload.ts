import { createConnection } from "node:net";
import { appendFileSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import * as jsc from "bun:jsc";

type Command =
  | { type: "heap_snapshot"; requestId: string; artifactPath: string; resultPath?: string; includeJsc?: boolean }
  | { type: "heap_analyze"; requestId: string; artifactPath: string; resultPath?: string; includeJsc?: boolean }
  | { type: "cpu_profile"; requestId: string; artifactPath: string; resultPath?: string; durationMs?: number }
  | { type: "runtime_diagnose"; requestId: string; durationMs?: number; sampleIntervalMs?: number; forceGc?: boolean };

type HeapPoint = {
  ts: number;
  heapUsed: number;
};

type RuntimePoint = {
  ts: number;
  lagMs: number;
  cpuPercent: number;
  rss: number;
  heapUsed: number;
};

const host = process.env.BUNCORE_HOST;
const port = Number(process.env.BUNCORE_PORT || 0);
const token = process.env.BUNCORE_TOKEN;
const processId = Number(process.env.BUNCORE_PROCESS_ID || 0);
const processName = process.env.BUNCORE_PROCESS_NAME || "process";
const runtimeKind = process.versions.bun ? "bun" : "generic";

if (host && port && token && runtimeKind === "bun") {
  const TELEMETRY_INTERVAL_MS = 1000;
  const DETAIL_INTERVAL_MS = 5000;
  const MAX_HISTORY = 600;

  const socket = createConnection({ host, port });
  socket.unref?.();

  let buffer = "";
  let socketClosed = false;
  let telemetryTimer: ReturnType<typeof setInterval> | null = null;
  let lastTick = Bun.nanoseconds();
  let lastCpuUser = 0;
  let lastCpuSystem = 0;
  let lastCpuTs = Date.now();
  let lastDetailsTs = 0;
  let cachedDetails = {
    jscHeapStats: jsc.heapStats(),
    jscMemoryUsage: jsc.memoryUsage(),
    resourceUsage: process.resourceUsage(),
  };
  const heapHistory: HeapPoint[] = [];

  const clamp = (value: number, min: number, max: number) => Math.min(max, Math.max(min, value));

  const average = (values: number[]) => {
    if (values.length === 0) return 0;
    return values.reduce((sum, value) => sum + value, 0) / values.length;
  };

  const percentile = (values: number[], ratio: number) => {
    if (values.length === 0) return 0;
    const sorted = [...values].sort((a, b) => a - b);
    const index = Math.min(sorted.length - 1, Math.max(0, Math.ceil(sorted.length * ratio) - 1));
    return sorted[index];
  };

  const round = (value: number, digits = 2) => Number(value.toFixed(digits));

  const pushHeapHistory = (point: HeapPoint) => {
    heapHistory.push(point);
    if (heapHistory.length > MAX_HISTORY) {
      heapHistory.splice(0, heapHistory.length - MAX_HISTORY);
    }
  };

  const stopTelemetry = () => {
    if (telemetryTimer) {
      clearInterval(telemetryTimer);
      telemetryTimer = null;
    }
  };

  const shutdownAgent = () => {
    stopTelemetry();
    if (socketClosed) return;
    socketClosed = true;
    try {
      socket.end();
    } catch {}
    try {
      socket.destroy();
    } catch {}
  };

  const send = (message: unknown) => {
    if (socketClosed || socket.destroyed) return;
    try {
      socket.write(`${JSON.stringify(message)}\n`);
    } catch {}
  };

  const collectDetails = () => ({
    jscHeapStats: jsc.heapStats(),
    jscMemoryUsage: jsc.memoryUsage(),
    resourceUsage: process.resourceUsage(),
  });

  const collectSummary = () => {
    const mem = process.memoryUsage();
    const cpu = process.cpuUsage();
    const nowNs = Bun.nanoseconds();
    const driftMs = Math.max(0, Number(nowNs - lastTick) / 1e6 - TELEMETRY_INTERVAL_MS);
    lastTick = nowNs;
    const nowTs = Date.now();

    if (nowTs - lastDetailsTs >= DETAIL_INTERVAL_MS) {
      cachedDetails = collectDetails();
      lastDetailsTs = nowTs;
    }

    const cpuUserMs = cpu.user / 1000;
    const cpuSystemMs = cpu.system / 1000;
    const deltaCpuMs = (cpuUserMs - lastCpuUser) + (cpuSystemMs - lastCpuSystem);
    const deltaWallMs = Math.max(1, nowTs - lastCpuTs);
    const cpuPercent = Math.max(0, (deltaCpuMs / deltaWallMs) * 100);
    lastCpuUser = cpuUserMs;
    lastCpuSystem = cpuSystemMs;
    lastCpuTs = nowTs;

    const summary = {
      rss: mem.rss,
      heapUsed: mem.heapUsed,
      heapTotal: mem.heapTotal,
      external: mem.external,
      arrayBuffers: mem.arrayBuffers,
      cpuPercent: round(cpuPercent),
      cpuUser: cpuUserMs,
      cpuSystem: cpuSystemMs,
      gcFreed: null,
      runtimeLagMs: round(driftMs, 3),
      timestamp: nowTs,
    };

    pushHeapHistory({ ts: summary.timestamp, heapUsed: summary.heapUsed });

    return {
      summary,
      details: cachedDetails,
    };
  };

  const buildHeapAnalysis = (artifactPath: string, includeJsc = false) => {
    const snapshot = Bun.generateHeapSnapshot();
    const classNames = snapshot.nodeClassNames;
    const nodes = snapshot.nodes;
    const NODE_FIELDS = 6;
    const classMem = new Map<string, { count: number; size: number }>();
    let totalObjects = 0;
    let totalSize = 0;

    for (let i = 0; i < nodes.length; i += NODE_FIELDS) {
      const typeIdx = nodes[i];
      const selfSize = nodes[i + 3];
      const className = classNames[typeIdx] || `type_${typeIdx}`;
      const entry = classMem.get(className) || { count: 0, size: 0 };
      entry.count++;
      entry.size += selfSize;
      classMem.set(className, entry);
      totalObjects++;
      totalSize += selfSize;
    }

    const currentHeap = process.memoryUsage();
    const topClasses = [...classMem.entries()]
      .sort((a, b) => b[1].size - a[1].size)
      .slice(0, 20)
      .map(([name, value]) => ({
        class: name,
        count: value.count,
        size: value.size,
        pct: totalSize > 0 ? round((value.size / totalSize) * 100) : 0,
      }));

    const recent = heapHistory.slice(-60);
    let growth = { rate: 0, isLeaking: false, confidence: 0 };
    if (recent.length >= 2) {
      const first = recent[0];
      const last = recent[recent.length - 1];
      const deltaMinutes = Math.max(0.001, (last.ts - first.ts) / 60000);
      const rate = (last.heapUsed - first.heapUsed) / deltaMinutes;
      growth = {
        rate,
        isLeaking: rate > 1024 * 128,
        confidence: Math.min(1, recent.length / 60),
      };
    }

    mkdirSync(dirname(artifactPath), { recursive: true });
    writeFileSync(artifactPath, Bun.generateHeapSnapshot("v8", "arraybuffer"));
    if (includeJsc) {
      writeFileSync(`${artifactPath}.jsc.json`, JSON.stringify(snapshot));
    }

    return {
      currentHeap: {
        used: currentHeap.heapUsed,
        total: currentHeap.heapTotal,
        external: currentHeap.external,
      },
      growth,
      topClasses,
      topConsumers: topClasses.slice(0, 8).map((entry) => ({
        type: entry.class,
        count: entry.count,
        size: entry.size,
        percentage: entry.pct,
      })),
      artifactPath,
      totals: { totalObjects, totalSize },
    };
  };

  const buildCpuProfile = async (artifactPath: string, durationMs = 10_000) => {
    const profile = await jsc.profile(async () => {
      await Bun.sleep(durationMs);
    }, 1000);

    const tierMatches = [...profile.bytecodes.matchAll(/^([A-Za-z ]+):\s+(\d+)/gm)];
    const tierBreakdown = tierMatches.map((match) => ({
      tier: match[1].trim(),
      samples: Number(match[2]),
    }));

    const hotFunctions = profile.functions
      .split("\n")
      .map((line) => line.trim())
      .filter(Boolean)
      .slice(0, 20)
      .map((line) => ({ label: line }));

    mkdirSync(dirname(artifactPath), { recursive: true });
    writeFileSync(artifactPath, JSON.stringify(profile, null, 2));
    return {
      durationMs,
      hotFunctions,
      tierBreakdown,
      sampleCount: hotFunctions.length,
      artifactPath,
    };
  };

  const buildRuntimeDiagnosis = async (durationMs = 10_000, sampleIntervalMs = 100, forceGc = false) => {
    const duration = clamp(Math.trunc(durationMs || 10_000), 250, 120_000);
    const sampleInterval = clamp(Math.trunc(sampleIntervalMs || 100), 25, 1000);
    const startedAt = Date.now();
    const deadline = startedAt + duration;

    const beforeResource = process.resourceUsage();
    const beforeHeapStats = jsc.heapStats();
    const beforeJscMemory = jsc.memoryUsage();
    const samples: RuntimePoint[] = [];

    let previousCpu = process.cpuUsage();
    let previousTs = Date.now();
    let expectedWakeNs = Bun.nanoseconds() + sampleInterval * 1e6;

    while (Date.now() < deadline) {
      await Bun.sleep(sampleInterval);
      const nowNs = Bun.nanoseconds();
      const nowTs = Date.now();
      const lagMs = Math.max(0, Number(nowNs - expectedWakeNs) / 1e6);
      expectedWakeNs = nowNs + sampleInterval * 1e6;

      const mem = process.memoryUsage();
      const cpu = process.cpuUsage();
      const deltaCpuMs = ((cpu.user - previousCpu.user) + (cpu.system - previousCpu.system)) / 1000;
      const deltaWallMs = Math.max(1, nowTs - previousTs);
      const cpuPercent = Math.max(0, (deltaCpuMs / deltaWallMs) * 100);
      previousCpu = cpu;
      previousTs = nowTs;

      samples.push({
        ts: nowTs,
        lagMs,
        cpuPercent,
        rss: mem.rss,
        heapUsed: mem.heapUsed,
      });
    }

    const afterMem = process.memoryUsage();
    const afterResource = process.resourceUsage();
    const afterHeapStats = jsc.heapStats();
    const afterJscMemory = jsc.memoryUsage();

    const lagValues = samples.map((sample) => sample.lagMs);
    const cpuValues = samples.map((sample) => sample.cpuPercent);
    const rssValues = samples.map((sample) => sample.rss);
    const heapValues = samples.map((sample) => sample.heapUsed);

    const firstSample = samples[0];
    const lastSample = samples[samples.length - 1];
    const elapsedMinutes = Math.max(0.001, (Date.now() - startedAt) / 60000);

    let gcProbe: {
      requested: boolean;
      reportedFreedBytes: number | null;
      heapUsedBefore: number | null;
      heapUsedAfter: number | null;
      reclaimedHeapBytes: number | null;
    } = {
      requested: forceGc,
      reportedFreedBytes: null,
      heapUsedBefore: null,
      heapUsedAfter: null,
      reclaimedHeapBytes: null,
    };

    if (forceGc && typeof Bun.gc === "function") {
      gcProbe.heapUsedBefore = process.memoryUsage().heapUsed;
      gcProbe.reportedFreedBytes = Bun.gc(true) || 0;
      gcProbe.heapUsedAfter = process.memoryUsage().heapUsed;
      gcProbe.reclaimedHeapBytes = Math.max(0, gcProbe.heapUsedBefore - gcProbe.heapUsedAfter);
    }

    const heapDelta = firstSample && lastSample ? lastSample.heapUsed - firstSample.heapUsed : 0;
    const rssDelta = firstSample && lastSample ? lastSample.rss - firstSample.rss : 0;
    const lagP95 = percentile(lagValues, 0.95);
    const lagMax = lagValues.length > 0 ? Math.max(...lagValues) : 0;
    const cpuAvg = average(cpuValues);
    const cpuMax = cpuValues.length > 0 ? Math.max(...cpuValues) : 0;

    const suspicions: string[] = [];
    if (lagMax >= 150 && cpuAvg >= 70) {
      suspicions.push("High event-loop lag with sustained CPU usage suggests blocking JS or heavy synchronous native work.");
    }
    if (lagP95 >= 40 && cpuAvg < 50) {
      suspicions.push("Lag spikes without matching CPU pressure suggest waits on I/O, timers, or cross-thread coordination.");
    }
    if (heapDelta > 8 * 1024 * 1024) {
      suspicions.push("Heap climbed materially during the sample window; inspect retained objects with heap-analyze or a snapshot diff.");
    }
    if ((gcProbe.reclaimedHeapBytes || 0) > 0 && heapDelta > 0) {
      suspicions.push("Forced GC reclaimed memory, which points to short-lived churn rather than a pure retained leak.");
    }
    if (rssDelta > heapDelta + 16 * 1024 * 1024) {
      suspicions.push("RSS grew faster than JS heap, which often indicates native buffers, file/socket pressure, or external memory growth.");
    }
    if (suspicions.length === 0) {
      suspicions.push("No dominant bottleneck stood out in this sample window; combine diagnose with cpu profile or heap analysis for deeper attribution.");
    }

    return {
      process: {
        id: processId,
        name: processName,
        pid: process.pid,
        runtime: runtimeKind,
      },
      window: {
        durationMs: duration,
        sampleIntervalMs: sampleInterval,
        sampleCount: samples.length,
      },
      eventLoop: {
        avgLagMs: round(average(lagValues), 3),
        p95LagMs: round(lagP95, 3),
        maxLagMs: round(lagMax, 3),
        spikesOver50ms: lagValues.filter((value) => value >= 50).length,
        spikesOver100ms: lagValues.filter((value) => value >= 100).length,
      },
      cpu: {
        avgPercent: round(cpuAvg),
        maxPercent: round(cpuMax),
      },
      memory: {
        rssStart: firstSample?.rss ?? afterMem.rss,
        rssEnd: lastSample?.rss ?? afterMem.rss,
        rssMax: rssValues.length > 0 ? Math.max(...rssValues) : afterMem.rss,
        rssDelta,
        heapStart: firstSample?.heapUsed ?? afterMem.heapUsed,
        heapEnd: lastSample?.heapUsed ?? afterMem.heapUsed,
        heapMax: heapValues.length > 0 ? Math.max(...heapValues) : afterMem.heapUsed,
        heapDelta,
        heapGrowthPerMinute: round(heapDelta / elapsedMinutes),
      },
      jsc: {
        before: {
          heapStats: beforeHeapStats,
          memoryUsage: beforeJscMemory,
        },
        after: {
          heapStats: afterHeapStats,
          memoryUsage: afterJscMemory,
        },
      },
      gcProbe,
      resourceDelta: {
        userCPUTime: afterResource.userCPUTime - beforeResource.userCPUTime,
        systemCPUTime: afterResource.systemCPUTime - beforeResource.systemCPUTime,
        maxRSS: afterResource.maxRSS - beforeResource.maxRSS,
        minorPageFault: afterResource.minorPageFault - beforeResource.minorPageFault,
        majorPageFault: afterResource.majorPageFault - beforeResource.majorPageFault,
        fsRead: afterResource.fsRead - beforeResource.fsRead,
        fsWrite: afterResource.fsWrite - beforeResource.fsWrite,
        voluntaryContextSwitches: afterResource.voluntaryContextSwitches - beforeResource.voluntaryContextSwitches,
        involuntaryContextSwitches: afterResource.involuntaryContextSwitches - beforeResource.involuntaryContextSwitches,
      },
      recentSamples: samples.slice(-20).map((sample) => ({
        timestamp: sample.ts,
        lagMs: round(sample.lagMs, 3),
        cpuPercent: round(sample.cpuPercent),
        rss: sample.rss,
        heapUsed: sample.heapUsed,
      })),
      suspicions,
    };
  };

  const onCommand = async (command: Command) => {
    try {
      if (command.type === "heap_snapshot") {
        mkdirSync(dirname(command.artifactPath), { recursive: true });
        writeFileSync(command.artifactPath, Bun.generateHeapSnapshot("v8", "arraybuffer"));
        if (command.includeJsc) {
          writeFileSync(`${command.artifactPath}.jsc.json`, JSON.stringify(Bun.generateHeapSnapshot()));
        }
        if (command.resultPath) {
          mkdirSync(dirname(command.resultPath), { recursive: true });
          writeFileSync(command.resultPath, JSON.stringify({ artifactPath: command.artifactPath }, null, 2));
        }
        send({ action: "agent_result", authToken: token, requestId: command.requestId, payload: { artifactPath: command.artifactPath } });
        return;
      }

      if (command.type === "heap_analyze") {
        const result = buildHeapAnalysis(command.artifactPath, command.includeJsc);
        if (command.resultPath) {
          mkdirSync(dirname(command.resultPath), { recursive: true });
          writeFileSync(command.resultPath, JSON.stringify(result, null, 2));
        }
        send({ action: "agent_result", authToken: token, requestId: command.requestId, payload: result });
        return;
      }

      if (command.type === "cpu_profile") {
        const result = await buildCpuProfile(command.artifactPath, command.durationMs);
        if (command.resultPath) {
          mkdirSync(dirname(command.resultPath), { recursive: true });
          writeFileSync(command.resultPath, JSON.stringify(result, null, 2));
        }
        send({ action: "agent_result", authToken: token, requestId: command.requestId, payload: result });
        return;
      }

      const result = await buildRuntimeDiagnosis(command.durationMs, command.sampleIntervalMs, command.forceGc);
      send({ action: "agent_result", authToken: token, requestId: command.requestId, payload: result });
    } catch (error: any) {
      appendFileSync("/tmp/buncore-agent-errors.log", `${new Date().toISOString()} ${String(error?.stack || error)}\n`);
      send({ action: "agent_result", authToken: token, requestId: command.requestId, error: String(error?.message || error) });
    }
  };

  socket.on("connect", () => {
    cachedDetails = collectDetails();
    lastDetailsTs = Date.now();

    send({
      action: "agent_hello",
      authToken: token,
      payload: {
        processId,
        processName,
        pid: process.pid,
        runtime: "bun",
        versions: process.versions,
      },
    });

    telemetryTimer = setInterval(() => {
      send({
        action: "telemetry",
        authToken: token,
        payload: {
          processId,
          pid: process.pid,
          runtime: "bun",
          ...collectSummary(),
        },
      });
    }, TELEMETRY_INTERVAL_MS);
    telemetryTimer.unref?.();
  });

  socket.on("data", (chunk) => {
    buffer += chunk.toString("utf8");
    let index = buffer.indexOf("\n");
    while (index >= 0) {
      const line = buffer.slice(0, index).trim();
      buffer = buffer.slice(index + 1);
      if (line) {
        try {
          const message = JSON.parse(line);
          if (message?.action === "command" && message?.payload?.command) {
            void onCommand(message.payload.command);
          }
        } catch (error: any) {
          appendFileSync("/tmp/buncore-agent-errors.log", `${new Date().toISOString()} ${String(error?.stack || error)}\n`);
        }
      }
      index = buffer.indexOf("\n");
    }
  });

  socket.on("close", () => {
    socketClosed = true;
    stopTelemetry();
  });

  socket.on("error", (error) => {
    appendFileSync("/tmp/buncore-agent-errors.log", `${new Date().toISOString()} ${String(error?.stack || error)}\n`);
    shutdownAgent();
  });

  process.once("SIGTERM", shutdownAgent);
  process.once("SIGINT", shutdownAgent);
  process.once("beforeExit", shutdownAgent);
}
