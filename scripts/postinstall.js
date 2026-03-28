const { execSync } = require("child_process");
const path = require("path");
const fs = require("fs");

const root = path.resolve(__dirname, "..");
const ext = process.platform === "win32" ? ".exe" : "";
const binaryPath = path.join(root, "zig-out", "bin", `bpm2${ext}`);

// Skip if binary already exists (prebuilt)
if (fs.existsSync(binaryPath)) {
  console.log("bpm2: binary already exists, skipping build.");
  process.exit(0);
}

// Try to build with zig
try {
  console.log("bpm2: building from source with zig...");
  execSync("zig build -Doptimize=ReleaseFast", {
    cwd: root,
    stdio: "inherit",
  });
  console.log("bpm2: build complete.");
} catch (err) {
  console.error(
    "\nbpm2: zig build failed.\n" +
      "Please install Zig (https://ziglang.org/download/) and run:\n" +
      "  cd " + root + " && zig build\n"
  );
  // Don't fail install — user can build manually
  process.exit(0);
}
