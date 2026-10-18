[CmdletBinding(PositionalBinding = $false)]
param([string]$PackagePath = 'apps/karita/build/msix-store/karita-store.msix')
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
if (-not [IO.Path]::IsPathRooted($PackagePath)) { $PackagePath = Join-Path $repoRoot $PackagePath }
$package = (Resolve-Path -LiteralPath $PackagePath).Path
$appcert = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10/App Certification Kit/appcert.exe'
if (-not (Test-Path -LiteralPath $appcert)) { throw 'Windows App Certification Kit is not installed.' }
$reportDir = Join-Path $repoRoot ('build/wack/' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
Get-FileHash -LiteralPath $package -Algorithm SHA256 |
    Format-List | Out-File (Join-Path $reportDir 'package-hash.txt') -Encoding utf8
$report = Join-Path $reportDir 'report.xml'
$arguments = @('test', '-appxpackagepath', ('"' + $package + '"'),
    '-reportoutputpath', ('"' + $report + '"'))
$process = Start-Process -FilePath $appcert -ArgumentList $arguments `
    -WindowStyle Hidden -PassThru -Wait
$result = $process.ExitCode
Write-Output "WACK exit code: $result; report: $report"
if ($result -ne 0) { throw "WACK did not complete successfully (exit $result)." }
if (-not (Test-Path -LiteralPath $report)) {
    throw 'WACK did not create a report. Run in an active administrator desktop session; do not mark this as passed.'
}
[xml]$document = Get-Content -LiteralPath $report -Raw
$failedTests = @($document.REPORT.REQUIREMENTS.REQUIREMENT.TEST |
    Where-Object { $_.RESULT.InnerText -ne 'PASS' })
Write-Output "Overall result: $($document.REPORT.OVERALL_RESULT); individual non-PASS: $($failedTests.Count)"
foreach ($test in $failedTests) {
    Write-Output "$($test.NAME): $($test.RESULT.InnerText); optional=$($test.OPTIONAL)"
}
if ($document.REPORT.OVERALL_RESULT -ne 'PASS') { throw 'WACK overall result is not PASS. Review the report.' }
Write-Output 'Review individual optional findings as well. WACK PASS does not guarantee Store certification.'
