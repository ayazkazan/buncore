$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

function Get-Binary([string]$name) {
  $exe = Join-Path $root "zig-out/bin/$name.exe"
  if (Test-Path $exe) { return $exe }
  $plain = Join-Path $root "zig-out/bin/$name"
  if (Test-Path $plain) { return $plain }
  throw "Binary not found: $name"
}

function Cleanup-Processes {
  $patterns = @(
    [regex]::Escape((Join-Path $root "zig-out/bin/buncored")),
    [regex]::Escape((Join-Path $root "fixtures/test-app.ts")),
    [regex]::Escape((Join-Path $root "fixtures/worker.ts")),
    "fixtures/test-app.ts",
    "fixtures/worker.ts"
  )

  $procs = Get-CimInstance Win32_Process | Where-Object {
    $cmd = $_.CommandLine
    if (-not $cmd) { return $false }
    foreach ($pattern in $patterns) {
      if ($cmd -match $pattern) { return $true }
    }
    return $false
  }

  foreach ($proc in $procs) {
    try { Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop } catch {}
  }
}

function Invoke-Buncore([string[]]$args) {
  $buncore = Get-Binary "buncore"
  & $buncore @args
}

function Get-ProcessPid([string]$name) {
  $output = Invoke-Buncore @("info", $name) 2>&1 | Out-String
  $match = [regex]::Match($output, "PID:\s+(\d+)")
  if (-not $match.Success) {
    throw "Could not read PID for $name"
  }
  return $match.Groups[1].Value
}

try { Invoke-Buncore @("kill") | Out-Null } catch {}
Cleanup-Processes
Remove-Item "$HOME\.buncore\daemon.json","$HOME\.buncore\state.json" -ErrorAction SilentlyContinue

Write-Host "[smoke] build"
zig build | Out-Null

Write-Host "[smoke] start worker instances"
Invoke-Buncore @("start", "fixtures/worker.ts", "--name", "worker", "--instances", "2") | Out-Null
Start-Sleep -Seconds 2
Invoke-Buncore @("list")

Write-Host "[smoke] all-target operations"
Invoke-Buncore @("restart", "all") | Out-Null
Start-Sleep -Seconds 2
Invoke-Buncore @("flush", "all") | Out-Null

Write-Host "[smoke] save/stop/resurrect"
Invoke-Buncore @("save") | Out-Null
Invoke-Buncore @("stop", "worker-0") | Out-Null
Invoke-Buncore @("resurrect") | Out-Null
Start-Sleep -Seconds 2
Invoke-Buncore @("list")

Write-Host "[smoke] watch restart"
Invoke-Buncore @("start", "fixtures/test-app.ts", "--name", "watch-app", "--watch", "--watch-path", "fixtures") | Out-Null
Start-Sleep -Seconds 2
$before = Get-ProcessPid "watch-app"
(Get-Item "fixtures/test-app.ts").LastWriteTime = Get-Date
Start-Sleep -Seconds 3
$after = Get-ProcessPid "watch-app"
if ($before -eq $after) {
  throw "watch did not restart process"
}

Write-Host "[smoke] heap/profile"
Invoke-Buncore @("heap", "watch-app") | Out-Null
Invoke-Buncore @("heap-analyze", "watch-app") | Out-Null
Invoke-Buncore @("profile", "watch-app", "--duration", "1") | Out-Null

Write-Host "[smoke] dashboard"
Invoke-Buncore @("dashboard")
Invoke-WebRequest -UseBasicParsing "http://127.0.0.1:9716/api/processes" | Out-Null

Write-Host "[smoke] shutdown"
Invoke-Buncore @("kill") | Out-Null
Start-Sleep -Seconds 1
Cleanup-Processes

$leftovers = Get-CimInstance Win32_Process | Where-Object {
  $_.CommandLine -and ($_.CommandLine -match "buncored|fixtures/test-app.ts|fixtures/worker.ts")
}
if ($leftovers) {
  throw "process cleanup failed"
}

Write-Host "[smoke] ok"
