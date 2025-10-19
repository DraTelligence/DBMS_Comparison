param(
  [string]$ResultsRoot = "E:\workSpace\files\project\dbms_comparison\results" # 修改为你的 results 根目录
)

$ErrorActionPreference = "Stop"
$all = Get-ChildItem -Path $ResultsRoot -Recurse -Filter *.txt |
  Where-Object { $_.FullName -notmatch '\\plan\\' }   # 跳过 explain/plan 文件

$reTime = '^Time:\s+([0-9.]+)\s*(ms|s)'
function FirstTimeAfter([string[]]$lines, [int]$start){
  for ($i=$start; $i -lt $lines.Length; $i++){
    if ($lines[$i] -match $reTime){
      $v = [double]$matches[1]
      if ($matches[2] -eq 's'){ $v *= 1000 }
      return $v
    }
  }
  return $null
}
function FirstIntAfter([string[]]$lines, [int]$start){
  for ($i=$start; $i -lt $lines.Length; $i++){
    if ($lines[$i] -match '^\s*([0-9]+)\s*$'){ return [int64]$matches[1] }
  }
  return $null
}
function FirstTokenAfter([string[]]$lines, [int]$start){
  for ($i=$start; $i -lt $lines.Length; $i++){
    $t = $lines[$i].Trim()
    if ($t -ne '' -and $t -notmatch '^(BEGIN|COMMIT|ROLLBACK|SET|DROP TABLE|INSERT|UPDATE)'){
      return $t
    }
  }
  return $null
}
function FindIndex([string[]]$lines, [string]$pattern){
  for ($i=0; $i -lt $lines.Length; $i++){
    if ($lines[$i] -match $pattern){ return $i }
  }
  return -1
}

$rows = @()
foreach($f in $all){
  $text  = Get-Content -Raw -Encoding UTF8 -Path $f.FullName
  $lines = $text -split "`r?`n"

  $db      = if ($f.FullName -match "\\results\\([^\\]+)\\") { $matches[1] } else { "" }    # og / pg
  $profile = if ($f.FullName -match "\\(default|parity)\\") { $matches[1] } else { "" }
  $cache   = if ($f.FullName -match "\\(cold|hot)\\")      { $matches[1] } else { "" }
  $run     = if ($f.BaseName  -match "-r(\d+)-")           { [int]$matches[1] } else { 0 }
  $ts      = if ($f.BaseName  -match "-r\d+-(\d{8}_\d{6})"){ $matches[1] } else { "" }
  $relpath = $f.FullName.Substring($ResultsRoot.Length).TrimStart('\','/')

  $rec = [ordered]@{
    db=$db; profile=$profile; cache=$cache; run=$run; ts=$ts; file=$relpath
    work_mem=$null; dataset_rows=$null
    q1_ms=$null; q2_ms=$null; q3_ms=$null
    u1_target=$null; u1_update_rows=$null; u1_update_ms=$null
    u2_target=$null; u2_update_rows=$null; u2_update_ms=$null
    u3_sandbox_rows=$null; u3_ctas_rows=$null; u3_ctas_ms=$null; u3_update_rows=$null; u3_update_ms=$null
  }

  # WORK_MEM
  $iWM = FindIndex $lines '^===\s*WORK_MEM'
  if ($iWM -ge 0){ $rec.work_mem = FirstTokenAfter $lines ($iWM+1) }

  # DATASET_SIZE
  $iData = FindIndex $lines '^===\s*DATASET_SIZE'
  if ($iData -ge 0){ $rec.dataset_rows = FirstIntAfter $lines ($iData+1) }

  # Q1/2/3
  $iQ1 = FindIndex $lines '^===\s*Q1'; if ($iQ1 -ge 0){ $rec.q1_ms = FirstTimeAfter $lines $iQ1 }
  $iQ2 = FindIndex $lines '^===\s*Q2'; if ($iQ2 -ge 0){ $rec.q2_ms = FirstTimeAfter $lines $iQ2 }
  $iQ3 = FindIndex $lines '^===\s*Q3'; if ($iQ3 -ge 0){ $rec.q3_ms = FirstTimeAfter $lines $iQ3 }

  # U1
  $iU1 = FindIndex $lines '^===\s*U1'
  if ($iU1 -ge 0){
    $rec.u1_target = FirstIntAfter $lines ($iU1+1)
    for ($i=$iU1; $i -lt $lines.Length; $i++){
      if ($lines[$i] -match '^UPDATE\s+([0-9]+)'){
        $rec.u1_update_rows = [int]$matches[1]
        $rec.u1_update_ms   = FirstTimeAfter $lines $i
        break
      }
    }
  }

  # U2
  $iU2 = FindIndex $lines '^===\s*U2'
  if ($iU2 -ge 0){
    $rec.u2_target = FirstIntAfter $lines ($iU2+1)
    for ($i=$iU2; $i -lt $lines.Length; $i++){
      if ($lines[$i] -match '^UPDATE\s+([0-9]+)'){
        $rec.u2_update_rows = [int]$matches[1]
        $rec.u2_update_ms   = FirstTimeAfter $lines $i
        break
      }
    }
  }

  # U3（沙箱）
  $iU3 = FindIndex $lines '^===\s*U3'
  if ($iU3 -ge 0){
    # CTAS 行数+时间
    for ($i=$iU3; $i -lt $lines.Length; $i++){
      if ($lines[$i] -match '^INSERT\s+0\s+([0-9]+)'){
        $rec.u3_ctas_rows = [int]$matches[1]
        $rec.u3_ctas_ms   = FirstTimeAfter $lines $i
        break
      }
    }
    # 沙箱统计
    $iSand = FindIndex $lines '^SANDBOX_ROWS:'
    if ($iSand -ge 0){ $rec.u3_sandbox_rows = FirstIntAfter $lines ($iSand+1) }
    # UPDATE in sandbox
    for ($i=$iU3; $i -lt $lines.Length; $i++){
      if ($lines[$i] -match '^UPDATE\s+([0-9]+)'){
        $rec.u3_update_rows = [int]$matches[1]
        $rec.u3_update_ms   = FirstTimeAfter $lines $i
        break
      }
    }
  }

  $rows += New-Object psobject -Property $rec
}

$csv = Join-Path $ResultsRoot "metrics.csv"
$rows | Sort-Object db, profile, cache, run, ts | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $csv
Write-Host "metrics.csv -> $csv"
