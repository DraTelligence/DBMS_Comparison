param(
    [string]$ProjectRoot = "E:\workSpace\files\project\dbms_comparison",
    [string]$DbHost = "host.docker.internal",
    [int]   $Port = 5433,
    [string]$User = "postgres",
    [string]$Pass = $env:OGPASS,
    [string]$Db = "nyc",
    [string]$WorkMem = "64MB",
    [int]   $ColdRuns = 1,
    [int]   $HotRuns = 1,
    [string]$RestartContainerName = "pg18",
    [int]   $ReadyTimeoutSec = 120          
)

$ErrorActionPreference = "Stop"
if (-not $Pass) { $Pass = "" }      # 回退默认口令（可改）

# 目录
$SqlDir = Join-Path $ProjectRoot "db"
$OutRoot = Join-Path $ProjectRoot "results\pg\parity"
$OutCold = Join-Path $OutRoot   "cold"
$OutHot = Join-Path $OutRoot   "hot"
New-Item -ItemType Directory -Force -Path $OutCold, $OutHot | Out-Null

function Wait-DbReady {
    param([string]$label)
    $deadline = (Get-Date).AddSeconds($ReadyTimeoutSec)
    do {
        docker run --rm -e PGPASSWORD=$Pass postgres:latest `
            pg_isready -h $DbHost -p $Port -U $User -d $Db -t 1 | Out-Null
        if ($LASTEXITCODE -eq 0) { Start-Sleep -Seconds 2; return }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    throw "[$label] DB is not ready after $ReadyTimeoutSec seconds."
}

function Invoke-Bench([string]$cacheMode, [int]$iter) {
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $run = "og-parity-$cacheMode-r{0:D2}-$ts" -f $iter
    $outd = if ($cacheMode -eq "cold") { $OutCold } else { $OutHot }

    docker run --rm -e PGPASSWORD=$Pass `
        -v "${SqlDir}:/sql" -v "${outd}:/out" `
        --entrypoint bash postgres:latest `
        -lc "psql -X -v ON_ERROR_STOP=1 -v wm=$WorkMem -h $DbHost -p $Port -U $User -d $Db -f /sql/bench_parity.sql 2>&1 | tee /out/$run.txt"
}

# cold
for ($i = 1; $i -le $ColdRuns; $i++) {
    if ($RestartContainerName) {
        docker restart $RestartContainerName | Out-Null
    }
    Wait-DbReady "cold#$i"
    Invoke-Bench "cold" $i
}

# hot
for ($i = 1; $i -le $HotRuns; $i++) {
    Wait-DbReady "hot#$i"
    Invoke-Bench "hot" $i
}

Write-Host "Done. Results in: `n  $OutCold`n  $OutHot"