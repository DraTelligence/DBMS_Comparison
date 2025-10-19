param(
  [string]$ProjectRoot = "E:\workSpace\files\project\dbms_comparison",
  [string]$DbHost = "host.docker.internal",
  [int]   $Port = 5433,
  [string]$User = "postgres",
  [string]$Pass = $env:PGPASS,
  [string]$Db = "nyc",
  [string]$WorkMem = "64MB",
  [string]$RestartContainerName = "pg18",
  [int]   $ReadyTimeoutSec = 120          
)

$ErrorActionPreference = "Stop"
if (-not $Pass) { $Pass = "" }

$SqlDir = Join-Path $ProjectRoot "db"
$OutDir = Join-Path $ProjectRoot "results\pg\parity\plan"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Wait-DbReady([string]$label) {
  $deadline = (Get-Date).AddSeconds($ReadyTimeoutSec)
  do {
    docker run --rm -e PGPASSWORD=$Pass postgres:latest `
      pg_isready -h $DbHost -p $Port -U $User -d $Db -t 1 | Out-Null
    if ($LASTEXITCODE -eq 0) { Start-Sleep -Seconds 2; return }
    Start-Sleep -Seconds 2
  } while ((Get-Date) -lt $deadline)
  throw "[$label] DB not ready after $ReadyTimeoutSec s."
}

if ($RestartContainerName) {
  docker restart $RestartContainerName | Out-Null
}
Wait-DbReady "plan"

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$run = "pg-parity-plan-$ts"

docker run --rm -e PGPASSWORD=$Pass `
  -v "${SqlDir}:/sql" -v "${OutDir}:/out" `
  --entrypoint bash postgres:latest `
  -lc "psql -X -v ON_ERROR_STOP=1 -v wm=$WorkMem -h $DbHost -p $Port -U $User -d $Db -f /sql/bench_explain_parity.sql 2>&1 | tee /out/$run.txt"

Write-Host "Done -> $OutDir\$run.txt"
