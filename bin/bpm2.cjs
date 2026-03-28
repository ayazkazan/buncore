#!/usr/bin/env node

const { execFileSync } = require("child_process");
const path = require("path");

const binaryPath = path.join(__dirname, "..", "zig-out", "bin", "bpm2");

try {
  execFileSync(binaryPath, process.argv.slice(2), { stdio: "inherit" });
} catch (error) {
  console.error(`Failed to execute bpm2: ${error.message}`);
  process.exit(1);
}