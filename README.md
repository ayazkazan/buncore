# buncore - Modern Process Manager for Bun

A modern, Bun-optimized process manager with production-ready features.

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

## Quick Start

```bash
# Start a TypeScript application
buncore start server.ts --name api --instances 4

# Start with environment variables
buncore start app.ts --name web --env production

# Start from ecosystem file
buncore start ecosystem.config.js

# Monitor processes
buncore list
buncore info api

# Manage processes
buncore restart api
buncore stop api
buncore delete api
```

## Feature Comparison with PM2

### Why teams look at buncore next to PM2

**PM2 is the classic default. buncore is the modern Bun-first alternative.**

If PM2 is the familiar, battle-tested Node.js process manager, **buncore** is the more opinionated control plane for teams that want:
- **native-feeling Bun + TypeScript workflows**
- a **lean Zig daemon** instead of a JS-only control layer
- a **built-in local dashboard** for day-to-day operations
- **built-in diagnostics** like heap snapshots and CPU profiling from the same toolchain

The goal is not to replace PM2's history. The goal is to offer a cleaner developer and operator experience for modern Bun services.

> Legend: **✅ built-in** · **⚠️ supported with caveats / different workflow**

### Quick decision guide

| If you care most about... | Better fit | Why |
|---------------------------|------------|-----|
| Mature Node.js familiarity | **PM2** | Huge ecosystem, long operational history, widely known workflows |
| Bun-first developer experience | **buncore** | Built around Bun-native usage instead of adapting Node-era assumptions |
| Built-in local control room | **buncore** | Ships with its own browser dashboard and action surface |
| Traditional Node infrastructure compatibility | **PM2** | A very common default in existing Node-heavy teams |
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
| TypeScript execution experience | ✅ strong native Bun workflow | ⚠️ often ts-node / transpile-oriented setups | Cleaner DX for TS-first services |
| Cluster load balancing | ✅ SO_REUSEPORT-based clustering | ✅ cluster mode | Different implementation, same production goal |
| Container / foreground mode | ✅ `--no-daemon` | ✅ via `pm2-runtime` | Both can work in container environments |
| Ecosystem config support | ✅ JS / JSON ecosystem support | ✅ | Familiar deployment model for teams migrating from PM2 |
| Control-plane implementation | ✅ Zig daemon | ✅ Node.js daemon | buncore emphasizes a lean native systems-layer daemon |

### Why buncore feels more modern

- **Built for Bun, not retrofitted onto it**
  - You get a workflow that feels natural for Bun-native applications instead of adapter-heavy setup.
- **Diagnostics are first-class**
  - Heap snapshots and CPU profiling are exposed as product features, not left entirely to external tooling.
- **The dashboard is part of the product**
  - Local browser-based fleet visibility and control are available without needing a separate commercial layer.
- **The control plane is lean by design**
  - The Zig daemon aims for a modern, low-overhead operational core.

### Where PM2 still wins for some teams

- **It is the known quantity**
  - Many Node.js teams already know PM2, already document PM2, and already deploy with PM2.
- **Its ecosystem gravity is real**
  - Tutorials, blog posts, old infrastructure scripts, and team habits often already revolve around it.
- **It fits legacy Node-first environments naturally**
  - If your stack is centered around long-standing Node.js conventions, PM2 may still feel like the easiest default.

### Bottom line

Choose **PM2** if your priority is the most familiar Node.js process-manager path with broad ecosystem recognition.

Choose **buncore** if you want a more modern **Bun-oriented** process manager with a stronger built-in control surface, richer local diagnostics, and a control plane designed for today's Bun workflows.

## Advanced Features

### Cluster Mode with SO_REUSEPORT
```bash
# OS-level load balancing (Linux/macOS)
buncore start app.ts --name api --exec-mode cluster --instances 4
```

### Graceful Reload (Zero Downtime)
```bash
# Rolling restart without dropping connections
buncore reload api
```

### Separate Log Files
```bash
# Split stdout and stderr
buncore start app.ts --name api --out-file app.out.log --error-file app.err.log
```

### Exponential Backoff
```bash
# Smart restart delays: 100ms → 200ms → 400ms → ... → 15s
buncore start unstable-app.ts --exp-backoff-restart-delay 100
```

### Container Mode
```bash
# Run without daemon (Docker/K8s friendly)
buncore start app.ts --no-daemon
```

### Cron Restart
```bash
# Daily restart at midnight
buncore start app.ts --cron-restart "0 0 * * *"
```

## Ecosystem Configuration

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

## Web Dashboard

```bash
# Print the dashboard URL and monitoring endpoints
buncore dashboard
```

buncore prints the exact local dashboard URL for the running daemon. The dashboard port is chosen automatically, starting from `9716`.

## Commands

### Process Management
- `buncore start <script>` - Start application
- `buncore restart <name|id|all>` - Restart processes
- `buncore reload <name|id|all>` - Graceful reload (zero-downtime)
- `buncore stop <name|id|all>` - Stop processes
- `buncore delete <name|id|all>` - Delete processes
- `buncore kill` - Kill daemon and all processes

### Monitoring
- `buncore list` - List all processes
- `buncore info <name|id>` - Detailed process information
- `buncore logs <name|id>` - Show logs
- `buncore dashboard` - Print the web dashboard URL and monitoring API endpoints

### Scaling & Management
- `buncore scale <name> <number>` - Scale instances
- `buncore reset <name|all>` - Reset restart counters
- `buncore signal <signal> <name|id>` - Send custom signal

### Configuration
- `buncore startup` - Generate startup script
- `buncore unstartup` - Remove startup script
- `buncore save` - Save current process list
- `buncore resurrect` - Restore saved processes
- `buncore dump` - Dump process configuration

## Why buncore?

### ✨ Modern Runtime Support
- **Native TypeScript**: Run `.ts` files directly with Bun/Deno
- **Better Performance**: Zig-based daemon with minimal overhead
- **Container Ready**: `--no-daemon` mode for Docker/Kubernetes

### 🚀 Advanced Features
- **SO_REUSEPORT Clustering**: Modern OS-level load balancing
- **Smart Backoff**: Exponential restart delays prevent resource exhaustion
- **Cron Restart**: Built-in scheduled restarts for memory cleanup
- **Separate Logs**: stdout/stderr split with automatic rotation

### 🔧 Production Ready
- **Graceful Reload**: Zero-downtime deployments
- **Memory Management**: Auto-restart on memory limits
- **Signal Control**: Send arbitrary signals to processes
- **Startup Integration**: systemd/launchd service generation

## GitHub & Issues

- **Repository**: https://github.com/ayazkazan/buncore
- **Issues**: https://github.com/ayazkazan/buncore/issues
- **NPM Package**: https://www.npmjs.com/package/buncore-cli

## License

MIT