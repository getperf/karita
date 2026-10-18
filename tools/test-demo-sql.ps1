param([switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$harness = Join-Path $repo 'example/harness'
$executable = Join-Path $harness 'build/windows/x64/runner/Release/karita_harness.exe'
$runDir = Join-Path $repo ('build/demo-sql/' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
if (-not $SkipBuild) {
    Push-Location $harness
    try {
        & flutter build windows --release --target lib/demo_sql_probe.dart --dart-define=KARITA_DEMO=temp --dart-define=LOG_FORMAT=jsonl
        if ($LASTEXITCODE -ne 0) { throw 'Windows build failed' }
    } finally { Pop-Location }
}
if (-not (Test-Path -LiteralPath $executable)) { throw 'Probe executable not found' }
Get-Command sqlite3.exe -ErrorAction Stop | Out-Null

# この実行だけの本番パスを用意し、デモによる変更がないことを確認する。
$probeHome = Join-Path $runDir 'home'
New-Item -ItemType Directory -Path (Join-Path $probeHome 'config'), (Join-Path $probeHome 'credentials') -Force | Out-Null
$sentinels = @{
    'library.db' = 'production-db-sentinel'
    'config/device.json' = '{"schemaVersion":1,"log":{"level":"INFO","format":"jsonl"}}'
    'token.json' = 'token-sentinel'
    'credentials/sentinel.txt' = 'credential-sentinel'
}
foreach ($entry in $sentinels.GetEnumerator()) {
    [IO.File]::WriteAllText((Join-Path $probeHome $entry.Key), $entry.Value)
}
$previousHome = $env:KARITA_HOME
$previousProbe = $env:KARITA_DEMO_PROBE_DIR
$env:KARITA_HOME = $probeHome
$env:KARITA_DEMO_PROBE_DIR = $runDir
$ownedProcesses = @()
try {
    foreach ($phase in @('normal', 'crash', 'verify')) {
        $process = Start-Process -FilePath $executable -ArgumentList $phase -WorkingDirectory (Split-Path $executable) -WindowStyle Hidden -PassThru
        $ownedProcesses += $process
        if ($phase -eq 'crash') {
            $deadline = (Get-Date).AddSeconds(45)
            while (-not (Test-Path -LiteralPath (Join-Path $runDir 'crash.ready'))) {
                if ($process.HasExited) { throw 'Crash probe exited before ready' }
                if ((Get-Date) -gt $deadline) { throw 'Crash probe timed out' }
                Start-Sleep -Milliseconds 200
            }
            Stop-Process -Id $process.Id -Force
            $process.WaitForExit()
        } else {
            if (-not $process.WaitForExit(45000)) { throw "$phase probe timed out" }
            if ($process.ExitCode -ne 0) { throw "$phase probe failed; inspect $runDir" }
        }
        $phaseFile = Join-Path $runDir "$phase.json"
        $result = Get-Content -LiteralPath $phaseFile -Raw | ConvertFrom-Json
        if (-not $result.passed) { throw "$phase not passed" }
        foreach ($entry in $sentinels.GetEnumerator()) {
            if ([IO.File]::ReadAllText((Join-Path $probeHome $entry.Key)) -cne $entry.Value) {
                throw "Retained file changed: $($entry.Key)"
            }
        }
        Write-Output "$phase passed: $phaseFile"
    }
    $normal = Get-Content -LiteralPath (Join-Path $runDir 'normal.json') -Raw | ConvertFrom-Json
    $crash = Get-Content -LiteralPath (Join-Path $runDir 'crash.json') -Raw | ConvertFrom-Json
    $verify = Get-Content -LiteralPath (Join-Path $runDir 'verify.json') -Raw | ConvertFrom-Json
    $paths = @($normal.observations[0].db_path, $normal.observations[3].db_path, $crash.observations[0].db_path, $verify.observations[0].db_path)
    if (@($paths | Select-Object -Unique).Count -ne 4) { throw 'Session paths reused' }
    if (Test-Path -LiteralPath $normal.observations[-1].db_path) { throw 'Normal close left its DB' }
    $crashPath = $crash.observations[-1].db_path
    if (-not (Test-Path -LiteralPath $crashPath)) { throw 'Crash DB unexpectedly disappeared' }
    # 異常終了後のDBはOS回収方針のまま残す。再起動が再利用しないことを証明する。
    $oldCount = & sqlite3.exe -readonly $crashPath 'SELECT count(*) FROM loans;'
    if ($LASTEXITCODE -ne 0 -or $oldCount -ne '20') { throw 'Crash DB did not retain edits' }
    $logFile = Join-Path $probeHome 'logs/karita.log'
    $logRecords = @(Get-Content -LiteralPath $logFile | ForEach-Object { $_ | ConvertFrom-Json })
    $readyRecords = @($logRecords | Where-Object { $_.event -eq 'demo.ready' })
    if ($readyRecords.Count -ne 4) { throw 'Expected all 4 sessions in retained log' }
    $summary = [ordered]@{
        passed = $true
        run_dir = $runDir
        normal_pid = $normal.pid
        crash_pid = $crash.pid
        restart_pid = $verify.pid
        distinct_db_paths = $paths
        retained_files_unchanged = $true
        retained_log_sessions = $readyRecords.Count
        crash_db_retained_loans = 20
        restart_loans = $verify.observations[0].summary.loans
        restart_markers = $verify.observations[0].summary.marker_count
    }
    $summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runDir 'summary.json') -Encoding utf8
    $summary | ConvertTo-Json -Depth 5
} finally {
    foreach ($process in $ownedProcesses) {
        if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    }
    $env:KARITA_HOME = $previousHome
    $env:KARITA_DEMO_PROBE_DIR = $previousProbe
}
