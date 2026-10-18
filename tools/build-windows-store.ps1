# Build a Store submission package. Never copy a whole credentials directory.
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory = $true)][string]$DesktopCredentials,
    [string]$DefinesFile = '.env'
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$appRoot = Join-Path $repoRoot 'apps/karita'
$credentialsFile = (Resolve-Path -LiteralPath $DesktopCredentials).Path
$definesPath = if ([IO.Path]::IsPathRooted($DefinesFile)) {
    $DefinesFile
} else {
    Join-Path $repoRoot $DefinesFile
}
$definesPath = (Resolve-Path -LiteralPath $definesPath).Path

# Do not print credential values, even on validation failure.
try { $client = Get-Content -LiteralPath $credentialsFile -Raw | ConvertFrom-Json }
catch { throw 'Desktop credentials must be valid JSON.' }
if (-not $client.installed -or $client.web -or $client.type -eq 'service_account' -or
    [string]::IsNullOrWhiteSpace($client.installed.client_id) -or
    [string]::IsNullOrWhiteSpace($client.installed.client_secret)) {
    throw 'Provide Google Desktop OAuth credentials (installed.client_id/client_secret).'
}
# Keep only the fields consumed by the Desktop client, not unrelated input data.
$bundledClient = @{ installed = @{
    client_id = $client.installed.client_id
    client_secret = $client.installed.client_secret
} }
foreach ($field in @('auth_uri', 'token_uri')) {
    if ($client.installed.$field) { $bundledClient.installed[$field] = $client.installed.$field }
}
foreach ($line in (Get-Content -LiteralPath $definesPath)) {
    if ($line -match '^\s*KARITA_SEED\s*=\s*\S+' -or
        ($line -match '^\s*KARITA_DEMO\s*=\s*(.+)$' -and $Matches[1].Trim() -ne 'off')) {
        throw 'Store builds require KARITA_DEMO=off and no KARITA_SEED.'
    }
}

Push-Location $appRoot
try {
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }
    & flutter build windows --release "--dart-define-from-file=$definesPath"
    if ($LASTEXITCODE -ne 0) { throw 'Windows Release build failed.' }
    $bundleDir = Join-Path $appRoot 'build/windows/x64/runner/Release/data/credentials'
    New-Item -ItemType Directory -Path $bundleDir -Force | Out-Null
    if (Get-ChildItem -LiteralPath $bundleDir -Force | Where-Object Name -ne 'karita-core-desktop.json') {
        throw 'Unexpected files in the generated credentials directory. Inspect before packaging.'
    }
    $bundledPath = Join-Path $bundleDir 'karita-core-desktop.json'
    [IO.File]::WriteAllText($bundledPath, ($bundledClient | ConvertTo-Json -Depth 4),
        [Text.UTF8Encoding]::new($false))
    & dart run msix:build --build-windows false --store --sign-msix false `
        --install-certificate false --output-path build/msix-store --output-name karita-store
    if ($LASTEXITCODE -ne 0) { throw 'Store MSIX preparation failed.' }
    & (Join-Path $PSScriptRoot 'prepare-windows-msix.ps1')
    & dart run msix:pack --store --sign-msix false `
        --install-certificate false --output-path build/msix-store --output-name karita-store
    if ($LASTEXITCODE -ne 0) { throw 'Store MSIX packaging failed.' }
    $packagePath = Join-Path $appRoot 'build/msix-store/karita-store.msix'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($packagePath)
    try {
        $names = @($archive.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
        if ('data/credentials/karita-core-desktop.json' -notin $names) {
            throw 'Desktop credentials missing from generated MSIX.'
        }
        if ($names | Where-Object { $_ -match '(^|/)(token\.json|\.env|karita-core-android\.json)$' }) {
            throw 'Unexpected local credentials or build input in generated MSIX.'
        }
    } finally { $archive.Dispose() }
    Get-FileHash -LiteralPath $packagePath -Algorithm SHA256
} finally {
    Pop-Location
}
