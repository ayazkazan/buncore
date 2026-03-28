const { execSync } = require("child_process");
const https = require("https");
const http = require("http");
const path = require("path");
const fs = require("fs");
const { createGunzip } = require("zlib");

const root = path.resolve(__dirname, "..");
const pkg = require(path.join(root, "package.json"));
const version = pkg.version;

const ext = process.platform === "win32" ? ".exe" : "";
const binDir = path.join(root, "zig-out", "bin");
const binaryPath = path.join(binDir, `bpm2${ext}`);
const daemonPath = path.join(binDir, `bpm2d${ext}`);

// Skip if both binaries already exist
if (fs.existsSync(binaryPath) && fs.existsSync(daemonPath)) {
  console.log("bpm2: binaries already exist, skipping.");
  process.exit(0);
}

// Determine platform key
function getPlatformKey() {
  const platform = process.platform;
  const arch = process.arch;
  const map = {
    "linux-x64": "bpm2-linux-x64",
    "linux-arm64": "bpm2-linux-arm64",
    "darwin-x64": "bpm2-darwin-x64",
    "darwin-arm64": "bpm2-darwin-arm64",
    "win32-x64": "bpm2-win32-x64",
  };
  return map[`${platform}-${arch}`] || null;
}

// Follow redirects and download
function download(url) {
  return new Promise((resolve, reject) => {
    const client = url.startsWith("https") ? https : http;
    client
      .get(url, { headers: { "User-Agent": "bpm2-installer" } }, (res) => {
        if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
          return download(res.headers.location).then(resolve, reject);
        }
        if (res.statusCode !== 200) {
          return reject(new Error(`HTTP ${res.statusCode} for ${url}`));
        }
        resolve(res);
      })
      .on("error", reject);
  });
}

// Simple tar.gz extraction (only regular files)
function extractTarGz(stream, destDir) {
  return new Promise((resolve, reject) => {
    const gunzip = createGunzip();
    const chunks = [];

    stream.pipe(gunzip);

    gunzip.on("data", (chunk) => chunks.push(chunk));
    gunzip.on("error", reject);
    gunzip.on("end", () => {
      const buf = Buffer.concat(chunks);
      let offset = 0;

      fs.mkdirSync(destDir, { recursive: true });

      while (offset < buf.length) {
        // tar header is 512 bytes
        if (offset + 512 > buf.length) break;
        const header = buf.subarray(offset, offset + 512);

        // Check for end-of-archive (two 512-byte blocks of zeros)
        if (header.every((b) => b === 0)) break;

        const name = header.subarray(0, 100).toString("utf8").replace(/\0/g, "").trim();
        const sizeOctal = header.subarray(124, 136).toString("utf8").replace(/\0/g, "").trim();
        const size = parseInt(sizeOctal, 8) || 0;
        const typeFlag = String.fromCharCode(header[156]);

        offset += 512; // move past header

        if (typeFlag === "0" || typeFlag === "\0") {
          // Regular file
          if (name && size > 0) {
            const filePath = path.join(destDir, path.basename(name));
            const fileData = buf.subarray(offset, offset + size);
            fs.writeFileSync(filePath, fileData);
            fs.chmodSync(filePath, 0o755);
          }
        }

        // Data blocks are padded to 512 bytes
        offset += Math.ceil(size / 512) * 512;
      }

      resolve();
    });
  });
}

async function tryDownloadPrebuilt() {
  const platformKey = getPlatformKey();
  if (!platformKey) {
    console.log(`bpm2: no prebuilt binary for ${process.platform}-${process.arch}`);
    return false;
  }

  const tag = `v${version}`;
  const url = `https://github.com/ayazkazan/bpm2/releases/download/${tag}/${platformKey}.tar.gz`;

  console.log(`bpm2: downloading prebuilt binary from ${url}...`);

  try {
    const stream = await download(url);
    await extractTarGz(stream, binDir);

    if (fs.existsSync(binaryPath)) {
      console.log("bpm2: prebuilt binary installed successfully.");
      return true;
    }
    return false;
  } catch (err) {
    console.log(`bpm2: prebuilt download failed (${err.message}), trying zig build...`);
    return false;
  }
}

async function tryZigBuild() {
  try {
    console.log("bpm2: building from source with zig...");
    execSync("zig build -Doptimize=ReleaseFast", {
      cwd: root,
      stdio: "inherit",
    });
    console.log("bpm2: build complete.");
    return true;
  } catch (err) {
    return false;
  }
}

async function main() {
  // 1. Try prebuilt binary from GitHub Releases
  if (await tryDownloadPrebuilt()) return;

  // 2. Fallback: build from source
  if (await tryZigBuild()) return;

  // 3. Neither worked
  console.error(
    "\nbpm2: installation requires either:\n" +
      "  - A prebuilt release at https://github.com/ayazkazan/bpm2/releases\n" +
      "  - Zig compiler (https://ziglang.org/download/)\n" +
      "\nReinstall with: npm install -g bpm2-cli\n" +
      "Manual build: cd " + root + " && zig build -Doptimize=ReleaseFast\n"
  );
}

main().catch((err) => {
  console.error("bpm2: postinstall error:", err.message);
});
