# buncore

**A modern Bun-first process manager powered by a Zig control plane.**

buncore is built for teams who want more than a basic `start` / `restart` wrapper. It gives you:
- **fast lifecycle management** for Bun workloads
- **built-in browser dashboard** for local operations
- **heap snapshot and CPU profiling flows** from the same CLI
- **runtime diagnosis for event-loop lag, heap drift, and GC behavior**
- **cluster, watch, restart, scale, and save/resurrect** workflows in one tool

---

## Why buncore

### Built for modern Bun workflows
Instead of treating Bun as an afterthought, buncore is designed around Bun-first process management, TypeScript-friendly execution, and faster operational feedback loops.

### More than a daemon
buncore combines:
- a **Zig-based control plane**
- a **browser dashboard**
- **runtime diagnostics**
- **production lifecycle operations**

### Local-first control room
The dashboard is not an afterthought. You can inspect processes, review logs, watch metrics, and trigger actions like restart, reload, stop, delete, scale, and signal operations from the web panel.

---

## Installation

```bash
npm install -g buncore-cli
```

After installation, use the `buncore` command:

```bash
buncore start app.ts --name api
buncore list
buncore stop api
```

---

## 60-second quick start

```bash
# Start a TypeScript application
buncore start server.ts --name api --instances 4

# Start with environment variables
buncore start app.ts --name web --env production

# Start from ecosystem file
buncore start ecosystem.config.js

# Inspect the fleet
buncore list
buncore info api
buncore logs api --lines 100

# Operate the fleet
buncore restart api
buncore reload api
buncore scale api 8

# Open the web command center
buncore dashboard
```

---

## Product snapshot

| Area | What buncore gives you |
|------|-------------------------|
| Lifecycle | Start, stop, restart, reload, delete, scale, signal, reset |
| Reliability | Auto-restart, exponential backoff, memory restart, cron restart |
| Monitoring | Process list, detailed info, real-time metrics, log tailing |
| Diagnostics | Heap snapshot, heap analysis, CPU profiling |
| Operations | Save/resurrect, startup integration, update workflow |
| UX | Terminal UI + built-in browser dashboard |

---

## Built-in web dashboard

```bash
buncore dashboard
```

The dashboard prints the exact local URL for the active daemon and opens a browser-ready control surface for:
- fleet overview
- per-process actions
- resource charts
- log viewing
- scale and signal management
- creating and managing processes from the panel itself

The dashboard port is chosen automatically, starting from `9716`.

The dashboard frontend is built with **React + Vite** and uses a **WebSocket-based live snapshot stream** for real-time fleet updates.

---

## What buncore Gives You

buncore is designed to keep the full Bun operations loop in one place: launch, inspect, diagnose, recover, and persist.

### 1. Lifecycle control that stays fast

Use the core lifecycle commands when you want to operate one service or a whole fleet without leaving the CLI:

```bash
# Start one service
buncore start app.ts --name api

# Restart it after a deploy
buncore restart api

# Graceful rolling reload
buncore reload api

# Stop one process or the whole fleet
buncore stop api
buncore stop all
```

What this gives you:
- one command surface for start, stop, restart, reload, delete, reset, and signal workflows
- graceful stop behavior with configurable kill timeouts
- runtime scaling without rewriting config

```bash
# Scale a service group
buncore scale api 6

# Send a custom signal
buncore signal SIGUSR2 api
```

### 2. Built-in control room for local operations

The browser dashboard is part of the product, not an extra layer. It gives you a live fleet list, process actions, logs, runtime charts, launcher controls, and Bun diagnosis from the same screen.

```bash
buncore dashboard
```

From the dashboard you can:
- restart, reload, stop, delete, flush logs, and reset counters
- inspect per-process runtime details
- scale groups and send signals
- launch new processes from the UI
- run Bun runtime diagnosis directly from the inspector

### 3. Bun-first diagnostics you can actually use

buncore goes beyond generic process status and gives you Bun/JSC-focused tooling from the CLI:

```bash
# Capture a heap snapshot
buncore heap api

# Analyze retained memory structure
buncore heap-analyze api --jsc

# Record a CPU profile
buncore profile api --duration 15

# Sample event-loop lag, heap drift, RSS drift, and GC reclaim
buncore diagnose api --duration 10 --sample-interval 50 --gc
```

This is especially useful when you want to answer questions like:
- is the service CPU-bound or blocked on the event loop?
- is memory growth happening in JS heap or outside it?
- does forced GC reclaim most of the growth, or is memory being retained?
- which runtime signals should I inspect next?

### 4. Real runtime visibility, not just process status

You can inspect the fleet from the terminal, the dashboard, or both:

```bash
# Fleet snapshot
buncore list

# Live terminal monitor
buncore monit

# Full process detail
buncore info api

# Tail logs
buncore logs api --lines 200 --follow
```

What you get out of the box:
- CPU, RSS, heap, restart counters, and runtime lag
- stdout/stderr log handling
- live process charts in the dashboard
- structured process detail for debugging and operational checks

### 5. Production-oriented restart and resilience controls

buncore includes the controls you usually need after the first deploy, not just during local development:

```bash
# Restart if memory goes beyond the threshold
buncore start app.ts --name api --max-memory 512000000

# Add exponential backoff
buncore start unstable.ts --name worker --exp-backoff-restart-delay 100

# Schedule a restart
buncore start app.ts --name nightly --cron-restart "0 0 * * *"

# Run multiple instances with cluster mode
buncore start app.ts --name api --exec-mode cluster --instances 4
```

These features help with:
- crash-loop control
- memory protection
- scheduled recycling of long-lived workers
- multi-instance HTTP workloads

### 6. Save, restore, and boot your fleet

You can preserve the active fleet and bring it back later:

```bash
# Save the current process set
buncore save

# Restore it later
buncore resurrect

# Generate startup integration
buncore startup
```

This makes buncore useful not just as a dev helper, but as a repeatable local or server-side process control layer.

---

## Advanced features

### Cluster mode with SO_REUSEPORT
```bash
# OS-level load balancing (Linux/macOS)
buncore start app.ts --name api --exec-mode cluster --instances 4
```

### Graceful reload (zero downtime)
```bash
# Rolling restart without dropping connections
buncore reload api
```

### Separate log files
```bash
# Split stdout and stderr
buncore start app.ts --name api --out-file app.out.log --error-file app.err.log
```

### Exponential backoff
```bash
# Smart restart delays: 100ms → 200ms → 400ms → ... → 15s
buncore start unstable-app.ts --exp-backoff-restart-delay 100
```

### Container mode
```bash
# Run without daemon (Docker/K8s friendly)
buncore start app.ts --no-daemon
```

### Cron restart
```bash
# Daily restart at midnight
buncore start app.ts --cron-restart "0 0 * * *"
```

### Runtime diagnostics
```bash
# Capture a heap snapshot
buncore heap api

# Analyze the heap
buncore heap-analyze api

# Capture a CPU profile
buncore profile api --duration 15

# Run Bun runtime diagnosis
buncore diagnose api --duration 10 --sample-interval 50 --gc
```

---

## Ecosystem configuration

```javascript
// ecosystem.config.js
module.exports = {
  apps: [
    {
      name: "api",
      script: "server.ts",
      instances: 4,
      exec_mode: "cluster",
      env: {
        NODE_ENV: "development",
        PORT: 3000
      },
      env_production: {
        NODE_ENV: "production",
        PORT: 8000
      },
      max_memory_restart: "1G",
      log_file: "combined.log",
      out_file: "out.log",
      error_file: "err.log",
      cron_restart: "0 0 * * *",
      exp_backoff_restart_delay: 100
    }
  ]
};
```

This gives you an ecosystem-based deployment model with a Bun-first runtime experience.

---

## Commands

### Process management
- `buncore start <script|config>` — Start a script or ecosystem config
- `buncore restart <name|id|all>` — Restart processes
- `buncore reload <name|id|all>` — Graceful reload
- `buncore stop <name|id|all>` — Stop processes
- `buncore delete <name|id|all>` — Remove processes from management
- `buncore kill` — Stop the daemon and all managed processes

### Monitoring & diagnostics
- `buncore list` — Snapshot view of the fleet
- `buncore monit` — Live terminal monitor
- `buncore info <name|id>` — Detailed process profile
- `buncore logs <name|id>` — Tail process logs
- `buncore dashboard` — Print the dashboard URL and monitoring endpoints
- `buncore heap <name|id>` — Capture a heap snapshot
- `buncore heap-analyze <name|id>` — Analyze heap artifacts
- `buncore profile <name|id>` — Capture a CPU profile
- `buncore diagnose <name|id>` — Sample event-loop lag, heap drift, and GC behavior

### Scaling & lifecycle control
- `buncore scale <name> <number>` — Change instance count at runtime
- `buncore reset <name|all>` — Reset restart counters
- `buncore signal <signal> <name|id>` — Send a custom signal

### Web dashboard development
- `npm run web:dev` — Start the Vite development server for the dashboard
- `npm run web:build` — Build the production dashboard bundle into `web/dist`
- `npm run web:preview` — Preview the built dashboard bundle locally

### Persistence & boot integration
- `buncore save` — Save the current fleet state
- `buncore resurrect` — Restore the saved fleet
- `buncore startup` — Generate startup integration
- `buncore unstartup` — Remove startup integration
- `buncore update` — Save, restart daemon, and restore fleet
- `buncore ecosystem` — Generate a starter ecosystem config

---

## Ideal for

buncore is especially useful if you are building:
- Bun APIs and backend services
- TypeScript-first services you want to run directly
- multi-instance HTTP workloads
- worker fleets that need restart control and observability
- teams who want a **local dashboard + CLI + diagnostics** in one tool

---

## Why teams choose buncore

### Faster daily operations
You can move from `start` to `dashboard` to `logs` to `profile` without switching tools or layering on extra products.

### Better local observability
The built-in command center makes it easier to inspect the fleet visually while still keeping terminal-native workflows intact.

### Production-minded defaults
Graceful reload, restart strategies, log handling, scale operations, and lifecycle persistence are all designed for real operational use.

---

## GitHub & issues

- **Repository**: https://github.com/ayazkazan/buncore
- **Issues**: https://github.com/ayazkazan/buncore/issues
- **NPM Package**: https://www.npmjs.com/package/buncore-cli

## License

MIT
