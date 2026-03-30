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

Both **buncore** and **PM2** solve the same core problem: keeping application processes alive, observable, and easy to operate in production.

The difference is in emphasis:
- **PM2** is the long-established, general-purpose Node.js process manager.
- **buncore** is a more modern, **Bun-first** control plane with a **Zig daemon**, built-in diagnostics, and a richer built-in local dashboard workflow.

> Legend: **✅ built-in** · **⚠️ supported with caveats / different workflow**

### Lifecycle & orchestration

| Capability | buncore | PM2 | Notes |
|-----------|---------|-----|-------|
| Start / stop / restart / delete | ✅ | ✅ | Core lifecycle management is covered by both |
| Zero-downtime reload | ✅ | ✅ | Graceful reload for production updates |
| Runtime scaling | ✅ `buncore scale api 8` | ✅ | Horizontal scaling at runtime |
| Watch mode / file-based restart | ✅ | ✅ | Useful in development and iterative staging workflows |
| Custom signal handling | ✅ | ✅ | Send `SIGTERM`, `SIGUSR1`, `SIGUSR2`, etc. |
| Auto-restart on crashes | ✅ | ✅ | Unexpected exits can be recovered automatically |
| Exponential backoff restart | ✅ | ✅ | Helps avoid tight crash loops under failure |
| Memory limit restart | ✅ | ✅ | Guardrail for long-running services |
| Cron-based restart | ✅ | ✅ | Useful for scheduled recycling / housekeeping |
| Save & resurrect process list | ✅ | ✅ | Persist and restore managed fleets |
| Startup integration | ✅ systemd / launchd | ✅ | Boot-time process restoration |

### Observability & diagnostics

| Capability | buncore | PM2 | Notes |
|-----------|---------|-----|-------|
| Process list / status overview | ✅ | ✅ | Fast fleet-level visibility |
| Detailed process inspection | ✅ | ✅ | Runtime, uptime, memory, restart history |
| Log streaming & tailing | ✅ | ✅ | Per-process log inspection |
| Separate stdout / stderr logs | ✅ | ✅ | Cleaner troubleshooting in production |
| Log rotation support | ✅ | ✅ | Prevents unbounded log growth |
| Real-time metrics | ✅ | ✅ | CPU / memory monitoring workflows |
| Built-in web dashboard | ✅ local dashboard included | ⚠️ richer web UI usually via PM2 Plus / separate tooling | buncore ships with a local browser-based control room |
| Heap snapshots | ✅ built-in command flow | ⚠️ usually external tooling / inspector workflow | Useful for memory leak analysis |
| CPU profiling | ✅ built-in command flow | ⚠️ usually external tooling / inspector workflow | Helpful for performance investigations |
| JSON-friendly outputs / API style | ✅ | ✅ | Better scripting and automation support |

### Runtime & platform fit

| Capability | buncore | PM2 | Notes |
|-----------|---------|-----|-------|
| Bun-first workflow | ✅ | ⚠️ possible via interpreter, but not Bun-native | buncore is designed around Bun-centric usage |
| TypeScript execution experience | ✅ strong native Bun workflow | ⚠️ commonly ts-node / transpile-based setups | Less ceremony for TS-first apps |
| Cluster load balancing | ✅ SO_REUSEPORT-based clustering | ✅ cluster mode | Different implementation strategy, same goal |
| Container / foreground mode | ✅ `--no-daemon` | ✅ via `pm2-runtime` | Both can fit container workflows |
| Ecosystem config support | ✅ JS / JSON ecosystem support | ✅ | Familiar deployment model |
| Control-plane implementation | ✅ Zig daemon | ✅ Node.js daemon | buncore emphasizes a lean native daemon |

### Where buncore stands out

- **Bun-first ergonomics** for teams that want a process manager aligned with modern Bun workflows.
- **Built-in local web dashboard** instead of pushing advanced browser-based visibility into a separate product tier.
- **Built-in heap snapshot and CPU profiling flows** for deeper diagnostics from the same toolchain.
- **Zig-based daemon architecture** focused on low overhead and a modern systems-level control plane.

### Where PM2 is still strong

- **Mature ecosystem and mindshare** across traditional Node.js deployments.
- **Longer operational history** in teams already standardized on Node-first infrastructure.
- **Large amount of community documentation** and established workflows.

In short: if you want a battle-tested general-purpose Node.js manager, PM2 is still the familiar baseline. If you want a more modern **Bun-oriented** experience with built-in diagnostics and a stronger local control surface, **buncore** is the more opinionated choice.

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