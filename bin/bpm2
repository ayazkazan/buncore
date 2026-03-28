#!/usr/bin/env node
const { execFileSync } = require("child_process");
const path = require("path");
const fs = require("fs");

const root = path.resolve(__dirname, "..");
const ext = process.platform === "win32" ? ".exe" : "";
const binaryPath = path.join(root, "zig-out", "bin", `bpm2${ext}`);

if (!fs.existsSync(binaryPath)) {
  console.error(
    "bpm2: binary not found at " + binaryPath + "\n" +
    "Run 'npm run build' or reinstall: npm install -g bpm2"
  );
  process.exit(1);
}

try {
  execFileSync(binaryPath, process.argv.slice(2), {
    stdio: "inherit",
    env: {
      ...process.env,
      BPM2_DAEMON_PATH: path.join(root, "zig-out", "bin", `bpm2d${ext}`),
    },
  });
} catch (err) {
  process.exit(err.status ?? 1);
}
