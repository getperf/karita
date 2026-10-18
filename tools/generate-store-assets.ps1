# Resize the existing brand master; do not change its design.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$repoRoot = Split-Path $PSScriptRoot -Parent
$brandDir = Join-Path $repoRoot 'assets/branding/karita-icon/v1'
$outputDir = Join-Path $brandDir 'store'
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$source = [Drawing.Image]::FromFile((Join-Path $brandDir 'icon-1024.png'))
try {
    $bitmap = [Drawing.Bitmap]::new(300, 300)
    try {
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        try {
            $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $graphics.DrawImage($source, 0, 0, 300, 300)
        } finally { $graphics.Dispose() }
        $bitmap.Save((Join-Path $outputDir 'app-tile-300.png'), [Drawing.Imaging.ImageFormat]::Png)
    } finally { $bitmap.Dispose() }
} finally { $source.Dispose() }
Write-Output 'Generated Store app tile: 300 x 300 PNG.'
