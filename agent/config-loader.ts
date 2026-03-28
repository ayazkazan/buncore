const target = process.argv[2];
const envName = process.argv[3] || null; // --env <name> passed from CLI

if (!target) {
  console.error("config path is required");
  process.exit(1);
}

const mod = await import(new URL(target, `file://${process.cwd()}/`).href);
const raw = mod.default ?? mod;
const apps = Array.isArray(raw?.apps) ? raw.apps : [];

const normalized = apps.map((app: any, index: number) => {
  // Merge named environment variables (env_production, env_staging, etc.)
  let baseEnv: Record<string, string> = {};
  if (typeof app.env === "object" && app.env) {
    baseEnv = Object.fromEntries(Object.entries(app.env).map(([k, v]) => [String(k), String(v)]));
  }
  if (envName) {
    const envKey = `env_${envName}`;
    const namedEnv = app[envKey];
    if (typeof namedEnv === "object" && namedEnv) {
      Object.assign(baseEnv, Object.fromEntries(Object.entries(namedEnv).map(([k, v]) => [String(k), String(v)])));
    }
  }

  return {
    name: app.name ?? `app-${index}`,
    script: app.script ?? "",
    args: Array.isArray(app.args) ? app.args.map(String) : [],
    cwd: app.cwd ? String(app.cwd) : process.cwd(),
    interpreter: app.interpreter ? String(app.interpreter) : null,
    instances: Number(app.instances ?? 1),
    watch: Boolean(app.watch ?? false),
    watchPath: app.watchPath ?? app.watch_path ?? null,
    ignoreWatch: Array.isArray(app.ignoreWatch ?? app.ignore_watch) ? (app.ignoreWatch ?? app.ignore_watch).map(String) : [],
    maxMemoryRestart: Number(app.maxMemoryRestart ?? app.max_memory_restart ?? 0),
    env: baseEnv,
    autorestart: app.autorestart !== false,
    maxRestarts: Number(app.maxRestarts ?? app.max_restarts ?? 15),
    minUptime: Number(app.minUptime ?? app.min_uptime ?? 1000),
    restartDelay: Number(app.restartDelay ?? app.restart_delay ?? 100),
    outFile: app.outFile ?? app.out_file ?? null,
    errorFile: app.errorFile ?? app.error_file ?? null,
    execMode: app.execMode ?? app.exec_mode ?? null,
    expBackoffRestartDelay: Number(app.expBackoffRestartDelay ?? app.exp_backoff_restart_delay ?? 0),
    stopExitCodes: Array.isArray(app.stopExitCodes ?? app.stop_exit_codes) ? (app.stopExitCodes ?? app.stop_exit_codes).map(Number) : [],
    cronRestart: app.cronRestart ?? app.cron_restart ?? null,
    maxLogSize: Number(app.maxLogSize ?? app.max_log_size ?? 0),
    killTimeout: Number(app.killTimeout ?? app.kill_timeout ?? 6000),
  };
});

console.log(JSON.stringify({ apps: normalized }, null, 2));
