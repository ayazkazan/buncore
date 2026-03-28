# buncore - Modern Process Manager for Bun

A modern, Bun-optimized process manager with production-ready features.

## Installation

```bash
npm install -g buncore
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

| Feature | buncore | PM2 | Notes |
|---------|----------|-----|-------|
| **Core Process Management** | ✅ | ✅ | Start/stop/restart/delete |
| **Load Balancing** | ✅ Cluster mode with SO_REUSEPORT | ✅ Cluster mode | buncore uses modern OS-level load balancing |
| **Hot Reload** | ✅ Zero-downtime graceful reload | ✅ Graceful reload | |
| **Auto-restart** | ✅ With exponential backoff | ✅ | buncore has smarter backoff strategy |
| **Log Management** | ✅ Separate stdout/stderr + rotation | ✅ | |
| **Ecosystem Config** | ✅ JS/JSON support | ✅ | Compatible format |
| **Environment Management** | ✅ Named env switching | ✅ | |
| **Startup Scripts** | ✅ systemd/launchd generation | ✅ | |
| **Monitoring** | ✅ Real-time metrics | ✅ | Built-in web dashboard |
| **Memory Management** | ✅ Auto-restart on memory limit | ✅ | |
| **Cron Jobs** | ✅ Built-in cron restart | ❌ | |
| **Container Support** | ✅ `--no-daemon` mode | ❌ | Better for Docker/K8s |
| **Signal Handling** | ✅ Custom signal sending | ✅ | |
| **Runtime Scaling** | ✅ `buncore scale app 8` | ✅ | |
| **TypeScript Native** | ✅ Built for Bun/Deno | ⚠️ Requires transpilation | buncore runs TS directly |
| **Modern Runtime** | ✅ Zig + Node.js | ⚠️ Node.js only | Better performance |
| **JSON API** | ✅ `--json` output | ✅ | |
| **Web Dashboard** | ✅ Built-in | ✅ PM2 Plus (separate) | |

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
# Start built-in monitoring dashboard
buncore web
# Open http://localhost:9615
```

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
- `buncore web` - Web-based monitoring dashboard

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
- **NPM Package**: https://www.npmjs.com/package/buncore

## License

MIT