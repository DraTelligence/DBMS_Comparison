# og_load_and_bench.ps1 — openGauss: rebuild -> import -> bench
$ErrorActionPreference = "Stop"
$DataDir = "E:\workSpace\files\project\dbms_comparison\data\raw"
$CsvName = "yellow_2019_07.csv"
$Schema = "schema_all.sql"
$OutDir = "E:\workSpace\files\project\dbms_comparison\results\og"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# Connection
$DBHost = "host.docker.internal"
$Port = 8888
$User = "gaussdb"
$Pass = ""
$Db = "nyc"

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$benchOut = Join-Path $OutDir "og_bench_$ts.txt"
$planOut = Join-Path $OutDir "og_explain_$ts.txt"

# 1) Build Database
docker run --rm -e PGPASSWORD=$Pass postgres:latest `
  psql -h $DbHost -p $Port -U $User -d postgres -c "CREATE DATABASE $Db"


# 2) Rebuild schema
docker run --rm -e PGPASSWORD="$Pass" -v "${DataDir}:/data" -it postgres:latest `
  psql -h $DBHost -p $Port -U $User -d $Db -v ON_ERROR_STOP=1 -f "/data/$Schema"

# 3) Import CSV
docker run --rm -e PGPASSWORD="$Pass" -v "${DataDir}:/data" -it postgres:latest `
  psql -h $DBHost -p $Port -U $User -d $Db `
  -c "\copy yellow_trips FROM '/data/$CsvName' WITH (FORMAT csv, HEADER true, NULL '')"

Write-Host "Done. See:`n  $benchOut`n  $planOut"
