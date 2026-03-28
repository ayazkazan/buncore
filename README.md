# bpm2-cli - Modern Process Manager for Bun

A modern, Bun-optimized process manager with production-ready features.

## Installation

```bash
npm install -g bpm2-cli
```

After installation, use the `bpm2` command:

```bash
bpm2 start app.ts --name api
bpm2 list
bpm2 stop api
```

## Quick Start

```bash
# Start a TypeScript application
bpm2 start server.ts --name api --instances 4

# Start with environment variables
bpm2 start app.ts --name web --env production

# Start from ecosystem file
bpm2 start ecosystem.config.js

# Monitor processes
bpm2 list
bpm2 info api

# Manage processes
bpm2 restart api
bpm2 stop api
bpm2 delete api
```

## Feature Comparison with PM2

| Feature | bpm2-cli | PM2 | Notes |
|---------|----------|-----|-------|
| **Core Process Management** | ✅ | ✅ | Start/stop/restart/delete |
| **Load Balancing** | ✅ Cluster mode with SO_REUSEPORT | ✅ Cluster mode | bpm2 uses modern OS-level load balancing |
| **Hot Reload** | ✅ Zero-downtime graceful reload | ✅ Graceful reload | |
| **Auto-restart** | ✅ With exponential backoff | ✅ | bmp2 has smarter backoff strategy |
| **Log Management** | ✅ Separate stdout/stderr + rotation | ✅ | |
| **Ecosystem Config** | ✅ JS/JSON support | ✅ | Compatible format |
| **Environment Management** | ✅ Named env switching | ✅ | |
| **Startup Scripts** | ✅ systemd/launchd generation | ✅ | |
| **Monitoring** | ✅ Real-time metrics | ✅ | Built-in web dashboard |
| **Memory Management** | ✅ Auto-restart on memory limit | ✅ | |
| **Cron Jobs** | ✅ Built-in cron restart | ❌ | |
| **Container Support** | ✅ `--no-daemon` mode | ❌ | Better for Docker/K8s |
| **Signal Handling** | ✅ Custom signal sending | ✅ | |
| **Runtime Scaling** | ✅ `bpm2 scale app 8` | ✅ | |
| **TypeScript Native** | ✅ Built for Bun/Deno | ⚠️ Requires transpilation | bpm2 runs TS directly |
| **Modern Runtime** | ✅ Zig + Node.js | ⚠️ Node.js only | Better performance |
| **JSON API** | ✅ `--json` output | ✅ | |
| **Web Dashboard** | ✅ Built-in | ✅ PM2 Plus (separate) | |

## Advanced Features

### Cluster Mode with SO_REUSEPORT
```bash
# OS-level load balancing (Linux/macOS)
bpm2 start app.ts --name api --exec-mode cluster --instances 4
```

### Graceful Reload (Zero Downtime)
```bash
# Rolling restart without dropping connections
bpm2 reload api
```

### Separate Log Files
```bash
# Split stdout and stderr
bpm2 start app.ts --name api --out-file app.out.log --error-file app.err.log
```

### Exponential Backoff
```bash
# Smart restart delays: 100ms → 200ms → 400ms → ... → 15s
bpm2 start unstable-app.ts --exp-backoff-restart-delay 100
```

### Container Mode
```bash
# Run without daemon (Docker/K8s friendly)
bpm2 start app.ts --no-daemon
```

### Cron Restart
```bash
# Daily restart at midnight
bpm2 start app.ts --cron-restart "0 0 * * *"
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
bpm2 web
# Open http://localhost:9615
```

## Commands

### Process Management
- `bpm2 start <script>` - Start application
- `bpm2 restart <name|id|all>` - Restart processes
- `bpm2 reload <name|id|all>` - Graceful reload (zero-downtime)
- `bpm2 stop <name|id|all>` - Stop processes
- `bpm2 delete <name|id|all>` - Delete processes
- `bpm2 kill` - Kill daemon and all processes

### Monitoring
- `bpm2 list` - List all processes
- `bpm2 info <name|id>` - Detailed process information
- `bpm2 logs <name|id>` - Show logs
- `bpm2 web` - Web-based monitoring dashboard

### Scaling & Management
- `bpm2 scale <name> <number>` - Scale instances
- `bpm2 reset <name|all>` - Reset restart counters
- `bpm2 signal <signal> <name|id>` - Send custom signal

### Configuration
- `bpm2 startup` - Generate startup script
- `bpm2 unstartup` - Remove startup script
- `bpm2 save` - Save current process list
- `bpm2 resurrect` - Restore saved processes
- `bpm2 dump` - Dump process configuration

## Why bpm2-cli?

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

- **Repository**: https://github.com/ayazkazan/bpm2
- **Issues**: https://github.com/ayazkazan/bpm2/issues
- **NPM Package**: https://www.npmjs.com/package/bpm2-cli

## License

MIT