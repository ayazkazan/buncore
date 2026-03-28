import { createConnection } from "node:net";
import { appendFileSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import * as jsc from "bun:jsc";

type Command =
  | { type: "heap_snapshot"; requestId: string; artifactPath: string; resultPath?: string; includeJsc?: boolean }
  | { type: "heap_analyze"; requestId: string; artifactPath: string; resultPath?: string; includeJsc?: boolean }
  | { type: "cpu_profile"; requestId: string; artifactPath: string; resultPath?: string; durationMs?: number };

const host = process.env.BPM2_HOST;
const port = Number(process.env.BPM2_PORT || 0);
const token = process.env.BPM2_TOKEN;
const processId = Number(process.env.BPM2_PROCESS_ID || 0);
const processName = process.env.BPM2_PROCESS_NAME || "process";
const runtimeKind = process.versions.bun ? "bun" : "generic";

if (host && port && token && runtimeKind === "bun") {
  const socket = createConnection({ host, port });
  let buffer = "";
  let lastTick = Bun.nanoseconds();
  let lastCpuUser = 0;
  let lastCpuSystem = 0;
  let lastCpuTs = Date.now();
  const heapHistory: Array<{ ts: number; heapUsed: number }> = [];

  const send = (message: unknown) => {
    socket.write(`${JSON.stringify(message)}\n`);
  };

  const collectSummary = () => {
    const mem = process.memoryUsage();
    const cpu = process.cpuUsage();
    const resources = process.resourceUsage();
    const nowNs = Bun.nanoseconds();
    const driftMs = Math.max(0, Number(nowNs - lastTick) / 1e6 - 1000);
    lastTick = nowNs;
    const nowTs = Date.now();
    const heapStats = jsc.heapStats();
    const jscMemory = jsc.memoryUsage();
    const gcFreed = typeof Bun.gc === "function" ? Bun.gc(false) || 0 : 0;
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
      cpuPercent: Number(cpuPercent.toFixed(2)),
      cpuUser: cpuUserMs,
      cpuSystem: cpuSystemMs,
      gcFreed,
      runtimeLagMs: Number(driftMs.toFixed(3)),
      timestamp: nowTs,
    };

    heapHistory.push({ ts: summary.timestamp, heapUsed: summary.heapUsed });
    if (heapHistory.length > 600) heapHistory.splice(0, heapHistory.length - 600);

    return {
      summary,
      details: {
        jscHeapStats: heapStats,
        jscMemoryUsage: jscMemory,
        resourceUsage: resources,
      },
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
        pct: totalSize > 0 ? Number(((value.size / totalSize) * 100).toFixed(2)) : 0,
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
      }
    } catch (error: any) {
      appendFileSync("/tmp/bpm2-agent-errors.log", `${new Date().toISOString()} ${String(error?.stack || error)}\n`);
      send({ action: "agent_result", authToken: token, requestId: command.requestId, error: String(error?.message || error) });
    }
  };

  socket.on("connect", () => {
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

    setInterval(() => {
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
    }, 1000).unref?.();
  });

  socket.on("data", (chunk) => {
    buffer += chunk.toString("utf8");
    let index = buffer.indexOf("\n");
    while (index >= 0) {
      const line = buffer.slice(0, index).trim();
      buffer = buffer.slice(index + 1);
      if (line) {
        const message = JSON.parse(line);
        if (message?.action === "command" && message?.payload?.command) {
          void onCommand(message.payload.command);
        }
      }
      index = buffer.indexOf("\n");
    }
  });
}
