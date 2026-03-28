# bpm2

A fast, zero-dependency process manager built in Zig for **Bun** workloads.
Think PM2, but native to Bun with deep runtime introspection.

## Features

- **Process Management** — start, stop, restart, reload, delete, scale
- **Cluster Mode** — `SO_REUSEPORT` based load balancing with `BPM2_INSTANCE_ID`
- **Graceful Reload** — zero-downtime rolling instance replacement
- **Watch Mode** — native inotify/kqueue/ReadDirectoryChangesW + polling fallback
- **Monitoring** — terminal monit, web dashboard, 600-point metric history
- **Bun Preload Agent** — heap snapshots, leak detection, CPU profiling, JSC metrics
- **Log Management** — separate stdout/stderr files, rotation, flush
- **Restart Strategies** — exponential backoff, exit code filtering, cron restart
- **Startup Scripts** — systemd (Linux) and launchd (macOS) integration
- **Container Mode** — `--no-daemon` foreground mode for Docker
- **Named Environments** — `env_production`, `env_staging` with `--env` switching
- **Signal Handling** — send arbitrary signals to processes
- **Zero Dependencies** — pure Zig daemon, no npm supply chain risk

## Install

### From npm

```bash
npm install -g bpm2
```

> Requires [Zig](https://ziglang.org/download/) to build from source during install.

### From source

```bash
git clone https://github.com/ayazkazan/bpm2.git
cd bpm2
zig build -Doptimize=ReleaseFast
```

Binary outputs to `./zig-out/bin/bpm2` and `./zig-out/bin/bpm2d`.

## Quick Start

```bash
# Start an app
bpm2 start app.ts --name api --instances 4 --exec-mode cluster

# Start from ecosystem config
bpm2 start ecosystem.config.ts --env production

# List processes
bpm2 list

# Monitor in real-time
bpm2 monit

# Graceful reload (zero downtime)
bpm2 reload api

# Scale at runtime
bpm2 scale api 8

# View logs
bpm2 logs api --follow

# Save and restore across reboots
bpm2 save
bpm2 startup
```

## Ecosystem Config

```typescript
// ecosystem.config.ts
export default {
  apps: [
    {
      name: "api",
      script: "./src/server.ts",
      instances: 4,
      exec_mode: "cluster",
      watch: true,
      ignore_watch: ["node_modules", ".git"],
      max_memory_restart: 256 * 1024 * 1024,
      exp_backoff_restart_delay: 100,
      stop_exit_codes: [0],
      cron_restart: "0 3 * * *",
      max_log_size: 10 * 1024 * 1024,
      out_file: "./logs/api-out.log",
      error_file: "./logs/api-err.log",
      env: {
        PORT: "3000",
      },
      env_production: {
        NODE_ENV: "production",
        PORT: "8080",
      },
    },
  ],
};
```

## Commands

| Command | Description |
|---------|-------------|
| `bpm2 start <script\|config> [options]` | Start a process or ecosystem |
| `bpm2 stop <name\|id\|all>` | Stop processes |
| `bpm2 restart <name\|id\|all>` | Restart processes |
| `bpm2 reload <name\|id\|all>` | Graceful rolling reload |
| `bpm2 delete <name\|id\|all>` | Remove processes |
| `bpm2 scale <name> <count>` | Scale instances up or down |
| `bpm2 list [--json]` | List all processes |
| `bpm2 info <name\|id> [--json]` | Detailed process info |
| `bpm2 monit` | Live terminal monitor |
| `bpm2 logs <name\|id> [--follow]` | View process logs |
| `bpm2 flush [name\|id\|all]` | Clear log files |
| `bpm2 signal <signal> <name\|id>` | Send signal to process |
| `bpm2 reset <name\|id\|all>` | Reset restart counters |
| `bpm2 save` | Save current fleet state |
| `bpm2 resurrect` | Restore saved fleet |
| `bpm2 startup` | Generate system boot script |
| `bpm2 unstartup` | Remove boot script |
| `bpm2 update` | Seamless daemon update |
| `bpm2 kill` | Stop all and shutdown daemon |
| `bpm2 dashboard` | Web dashboard URL |
| `bpm2 heap <name\|id>` | Heap snapshot |
| `bpm2 heap-analyze <name\|id>` | Heap analysis + leak detection |
| `bpm2 profile <name\|id>` | CPU profiling |
| `bpm2 ping` | Check daemon status |
| `bpm2 ecosystem` | Generate starter config |

## Start Options

| Flag | Description |
|------|-------------|
| `--name, -n` | Process name |
| `--instances, -i` | Number of instances |
| `--exec-mode` | `fork` (default) or `cluster` |
| `--watch, -w` | Watch for file changes |
| `--watch-path` | Custom watch directory |
| `--ignore-watch` | Comma-separated ignore patterns |
| `--cwd` | Working directory |
| `--interpreter` | Custom interpreter |
| `--env` | Environment name for config (production, staging) |
| `--max-memory` | Max memory before restart (bytes) |
| `--out-file, -o` | Stdout log file path |
| `--error-file, -e` | Stderr log file path |
| `--exp-backoff-restart-delay` | Initial backoff delay (ms), doubles up to 15s |
| `--cron-restart` | Cron expression for scheduled restarts |
| `--max-log-size` | Max log size before rotation (bytes) |
| `--kill-timeout` | Graceful shutdown timeout (ms, default 6000) |
| `--no-daemon` | Run in foreground (Docker/container mode) |

## Architecture

```
┌─────────┐    TCP/JSON    ┌──────────┐
│  bpm2    │ ◄────────────►│  bpm2d   │
│  (CLI)   │               │ (daemon) │
└─────────┘               └──────────┘
                                │
                    ┌───────────┼───────────┐
                    │           │           │
               ┌────┴───┐ ┌────┴───┐ ┌────┴───┐
               │ Process │ │ Process │ │ Process │
               │ + Agent │ │ + Agent │ │ + Agent │
               └────────┘ └────────┘ └────────┘
```

- **CLI** (`bpm2`): User-facing commands, sends JSON requests to daemon
- **Daemon** (`bpm2d`): Manages processes, metrics, watch, web dashboard
- **Agent** (`preload.ts`): Injected via `bun --preload`, provides runtime telemetry

## Layout

```
zig/src/       — CLI, daemon, protocol, render, storage, watch (Zig)
agent/         — Bun preload agent, config loader (TypeScript)
web/           — Dashboard static assets
bin/           — npm bin wrapper
scripts/       — postinstall build script
fixtures/      — Test apps
```

## License

MIT
