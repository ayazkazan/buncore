# buncore

**A modern Bun-first process manager powered by a Zig control plane.**

buncore is built for teams who want more than a basic `start` / `restart` wrapper. It gives you:
- **fast lifecycle management** for Bun workloads
- **built-in browser dashboard** for local operations
- **heap snapshot and CPU profiling flows** from the same CLI
- **cluster, watch, restart, scale, and save/resurrect** workflows in one tool

If PM2 is the familiar Node-era default, **buncore** is the more modern, more opinionated option for Bun-native projects.

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

---

## Feature Comparison with PM2

### Why teams compare buncore with PM2

**PM2 is the classic default. buncore is the modern Bun-first alternative.**

If your stack is heavily invested in long-standing Node.js workflows, PM2 still feels familiar. But if your priority is a more modern process manager with a stronger Bun experience, built-in diagnostics, and a richer local control surface, buncore is the more forward-looking choice.

> Legend: **✅ built-in** · **⚠️ supported with caveats / different workflow**

### Quick decision guide

| If you care most about... | Better fit | Why |
|---------------------------|------------|-----|
| Mature Node.js familiarity | **PM2** | Huge ecosystem, long operational history, widely known workflows |
| Bun-first developer experience | **buncore** | Built around Bun-native usage instead of adapting Node-era assumptions |
| Built-in local control room | **buncore** | Ships with its own browser dashboard and action surface |
| Traditional Node infrastructure compatibility | **PM2** | A common default in existing Node-heavy teams |
| Built-in diagnostic workflows | **buncore** | Heap snapshot and CPU profile flows are part of the tool itself |
| Lean, modern control-plane architecture | **buncore** | Zig daemon + modern process management focus |

### Head-to-head: lifecycle & orchestration

| Capability | buncore | PM2 | Why it matters |
|-----------|---------|-----|----------------|
| Start / stop / restart / delete | ✅ | ✅ | Core lifecycle control is covered on both sides |
| Zero-downtime reload | ✅ | ✅ | Safer deploys for HTTP and long-running services |
| Runtime scaling | ✅ `buncore scale api 8` | ✅ | Increase or shrink capacity without redesigning config |
| Watch mode / file-based restart | ✅ | ✅ | Faster iteration in dev, preview, and staging |
| Custom signal handling | ✅ | ✅ | Useful for graceful shutdowns and advanced runtime hooks |
| Auto-restart on crashes | ✅ | ✅ | Keeps critical services self-healing after unexpected exits |
| Exponential backoff restart | ✅ | ✅ | Prevents aggressive crash loops from burning CPU and logs |
| Memory limit restart | ✅ | ✅ | Protects hosts from runaway memory growth |
| Cron-based restart | ✅ | ✅ | Good for scheduled maintenance or long-lived worker recycling |
| Save & resurrect process list | ✅ | ✅ | Restore the same fleet after daemon restart or reboot |
| Startup integration | ✅ systemd / launchd | ✅ | Makes production boot flows predictable |

### Head-to-head: observability & diagnostics

| Capability | buncore | PM2 | Why it matters |
|-----------|---------|-----|----------------|
| Process list / status overview | ✅ | ✅ | Immediate visibility into the current fleet state |
| Detailed process inspection | ✅ | ✅ | Faster debugging of uptime, runtime, restart, and memory state |
| Log streaming & tailing | ✅ | ✅ | Daily operational troubleshooting depends on this |
| Separate stdout / stderr logs | ✅ | ✅ | Cleaner production debugging and incident analysis |
| Log rotation support | ✅ | ✅ | Prevents disks from silently filling with logs |
| Real-time metrics | ✅ | ✅ | Helps spot saturation and unhealthy services early |
| Built-in web dashboard | ✅ local dashboard included | ⚠️ richer web UI usually means PM2 Plus / extra tooling | buncore ships with a local browser-based command center |
| Heap snapshots | ✅ built-in command flow | ⚠️ usually external inspector workflow | Critical when chasing memory leaks |
| CPU profiling | ✅ built-in command flow | ⚠️ usually external inspector workflow | Helps explain slow endpoints and hot paths |
| JSON-friendly outputs / API style | ✅ | ✅ | Makes automation, CI scripts, and custom tooling easier |

### Head-to-head: runtime & platform fit

| Capability | buncore | PM2 | Why it matters |
|-----------|---------|-----|----------------|
| Bun-first workflow | ✅ | ⚠️ possible via interpreter, but not Bun-native | Less friction for Bun teams from day one |
| TypeScript execution experience | ✅ strong native Bun workflow | ⚠️ often transpile- or ts-node-oriented setups | Cleaner DX for TS-first services |
| Cluster load balancing | ✅ SO_REUSEPORT-based clustering | ✅ cluster mode | Different implementation, same production goal |
| Container / foreground mode | ✅ `--no-daemon` | ✅ via `pm2-runtime` | Both can work in container environments |
| Ecosystem config support | ✅ JS / JSON ecosystem support | ✅ | Familiar deployment model for teams migrating from PM2 |
| Control-plane implementation | ✅ Zig daemon | ✅ Node.js daemon | buncore emphasizes a lean native systems-layer daemon |

### Why buncore feels more modern

- **Built for Bun, not retrofitted onto it**
  - The workflow feels natural for Bun-native services.
- **Diagnostics are first-class**
  - Heap snapshots and CPU profiling are exposed as product features.
- **The dashboard is part of the product**
  - Local browser-based fleet visibility does not depend on a separate premium layer.
- **The control plane is lean by design**
  - The Zig daemon keeps the operational core focused and lightweight.

### Where PM2 still wins for some teams

- **It is the known quantity**
  - Many Node.js teams already know, document, and deploy with PM2.
- **Its ecosystem gravity is real**
  - Tutorials, scripts, and infrastructure habits often already revolve around it.
- **It fits legacy Node-first environments naturally**
  - If your platform is centered on established Node.js conventions, PM2 may still be the easy default.

### Bottom line

Choose **PM2** if your priority is the most familiar Node.js process-manager path with broad ecosystem recognition.

Choose **buncore** if you want a more modern **Bun-oriented** process manager with a stronger built-in control surface, richer local diagnostics, and a control plane designed for today's Bun workflows.

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

This gives you a PM2-style deployment model with a Bun-first runtime experience.

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

### Scaling & lifecycle control
- `buncore scale <name> <number>` — Change instance count at runtime
- `buncore reset <name|all>` — Reset restart counters
- `buncore signal <signal> <name|id>` — Send a custom signal

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
