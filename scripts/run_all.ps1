param(
  # 项目根目录
  [string]$ProjectRoot = "E:\workSpace\files\project\dbms_comparison",

  # 冷/热次数
  [int]$ColdRuns = 2,
  [int]$HotRuns = 2,

  # 是否运行 OG / PG 两套
  [switch]$RunOG = $true,
  [switch]$RunPG = $true,

  # 每步之间的间隔秒数
  [int]$SleepBetweenStepsSec = 3,

  # openGauss 连接与参数
  [string]$OGHost = "host.docker.internal",
  [int]   $OGPort = 8888,
  [string]$OGUser = "gaussdb",
  [string]$OGPass = $env:OGPASS,
  [string]$OGDb = "nyc",
  [string]$OGWorkMem = "64MB",
  [string]$OGContainer = "opengauss",
  [int]   $OGReadyTimeoutSec = 120,

  # PostgreSQL 连接与参数
  [string]$PGHost = "host.docker.internal",
  [int]   $PGPort = 5433,
  [string]$PGUser = "postgres",
  [string]$PGPass = $env:PGPASS,
  [string]$PGDb = "nyc",
  [string]$PGWorkMem = "64MB",
  [string]$PGContainer = "pg18",
  [int]   $PGReadyTimeoutSec = 120
)

# --- 读取 .env---
$DotenvPath = Join-Path $ProjectRoot ".env"
if (Test-Path $DotenvPath) {
  Get-Content -Raw -Encoding UTF8 $DotenvPath `
  | ForEach-Object {
    $_ -replace "`r`n", "`n" -replace "`r", "`n"
  } `
  | ForEach-Object {
    foreach ($line in $_.Split("`n")) {
      $t = $line.Trim()
      if ($t -eq "" -or $t.StartsWith("#")) { continue }
      $kv = $t.Split("=", 2)
      if ($kv.Count -eq 2) {
        $name = $kv[0].Trim()
        $val = $kv[1]
        if ($val.StartsWith('"') -and $val.EndsWith('"')) { $val = $val.Trim('"') }
        if ($val.StartsWith("'") -and $val.EndsWith("'")) { $val = $val.Trim("'") }
        Set-Item -Path "Env:$name" -Value $val
      }
    }
  }
}

# 用 .env 中的值填充参数（允许命令行覆盖 .env）
if ([string]::IsNullOrWhiteSpace($OGPass)) { $OGPass = $env:OGPASS }
if ([string]::IsNullOrWhiteSpace($PGPass)) { $PGPass = $env:PGPASS }

# 强制要求提供密码（更安全：不允许使用“默认回退密码”）
if ([string]::IsNullOrWhiteSpace($OGPass)) { throw "openGauss 密码缺失：请在 .env 设置 OGPASS 或通过 -OGPass 传入" }
if ([string]::IsNullOrWhiteSpace($PGPass)) { throw "PostgreSQL 密码缺失：请在 .env 设置 PGPASS 或通过 -PGPass 传入" }

$ErrorActionPreference = "Stop"
if (-not $OGPass) { $OGPass = "Opengauss@Drat0633" }
if (-not $PGPass) { $PGPass = "postgres" }

$Scripts = Join-Path $ProjectRoot "scripts"

function Invoke-Step($label, $scriptFile, $argsArray) {
  $scriptPath = Join-Path $Scripts $scriptFile
  if (-not (Test-Path $scriptPath)) { Write-Warning "Skip: $label (missing $scriptPath)"; return }
  Write-Host ">>> $label" -ForegroundColor Cyan
  & $scriptPath @argsArray
  if ($LASTEXITCODE -ne 0) { throw "Step failed: $label" }
  Start-Sleep -Seconds $SleepBetweenStepsSec
}

# ---------- openGauss ----------
if ($RunOG) {
  Invoke-Step "OG bench default (cold=$ColdRuns hot=$HotRuns)" "og\bench_default.ps1" @{
    ProjectRoot = $ProjectRoot; DbHost = $OGHost; Port = $OGPort; User = $OGUser; Pass = $OGPass; Db = $OGDb;
    ColdRuns = $ColdRuns; HotRuns = $HotRuns; RestartContainerName = $OGContainer; ReadyTimeoutSec = $OGReadyTimeoutSec
  }
  Invoke-Step "OG bench parity (wm=$OGWorkMem)" "og\bench_parity.ps1" @{
    ProjectRoot = $ProjectRoot; DbHost = $OGHost; Port = $OGPort; User = $OGUser; Pass = $OGPass; Db = $OGDb;
    WorkMem = $OGWorkMem; ColdRuns = $ColdRuns; HotRuns = $HotRuns; RestartContainerName = $OGContainer; ReadyTimeoutSec = $OGReadyTimeoutSec
  }
  Invoke-Step "OG explain default" "og\explain_default.ps1" @{
    ProjectRoot = $ProjectRoot; DbHost = $OGHost; Port = $OGPort; User = $OGUser; Pass = $OGPass; Db = $OGDb;
    RestartContainerName = $OGContainer; ReadyTimeoutSec = $OGReadyTimeoutSec
  }
  Invoke-Step "OG explain parity (wm=$OGWorkMem)" "og\explain_parity.ps1" @{
    ProjectRoot = $ProjectRoot; DbHost = $OGHost; Port = $OGPort; User = $OGUser; Pass = $OGPass; Db = $OGDb; WorkMem = $OGWorkMem;
    RestartContainerName = $OGContainer; ReadyTimeoutSec = $OGReadyTimeoutSec
  }
}

# ---------- PostgreSQL ----------
if ($RunPG) {
  Invoke-Step "PG bench default (cold=$ColdRuns hot=$HotRuns)" "pg\bench_default.ps1" @{
    ProjectRoot = $ProjectRoot; DbHost = $PGHost; Port = $PGPort; User = $PGUser; Pass = $PGPass; Db = $PGDb;
    ColdRuns = $ColdRuns; HotRuns = $HotRuns; RestartContainerName = $PGContainer; ReadyTimeoutSec = $PGReadyTimeoutSec
  }
  Invoke-Step "PG bench parity (wm=$PGWorkMem)" "pg\bench_parity.ps1" @{
    ProjectRoot = $ProjectRoot; DbHost = $PGHost; Port = $PGPort; User = $PGUser; Pass = $PGPass; Db = $PGDb; WorkMem = $PGWorkMem;
    ColdRuns = $ColdRuns; HotRuns = $HotRuns; RestartContainerName = $PGContainer; ReadyTimeoutSec = $PGReadyTimeoutSec
  }
  Invoke-Step "PG explain default" "pg\explain_default.ps1" @{
    ProjectRoot = $ProjectRoot; DbHost = $PGHost; Port = $PGPort; User = $PGUser; Pass = $PGPass; Db = $PGDb;
    RestartContainerName = $PGContainer; ReadyTimeoutSec = $PGReadyTimeoutSec
  }
  Invoke-Step "PG explain parity (wm=$PGWorkMem)" "pg\explain_parity.ps1" @{
    ProjectRoot = $ProjectRoot; DbHost = $PGHost; Port = $PGPort; User = $PGUser; Pass = $PGPass; Db = $PGDb; WorkMem = $PGWorkMem;
    RestartContainerName = $PGContainer; ReadyTimeoutSec = $PGReadyTimeoutSec
  }
}

# ---------- 汇总 metrics.csv ----------
$extract = Join-Path $Scripts "extract_metrics.ps1"
if (Test-Path $extract) {
  Invoke-Step "Extract metrics.csv" "extract_metrics.ps1" @{ ResultsRoot = (Join-Path $ProjectRoot "results") }
}
else {
  Write-Warning "Skip: extractor not found: $extract"
}

Write-Host "All steps done." -ForegroundColor Green