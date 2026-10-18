# アイコンの生成。**原本は assets/branding/karita-icon/v1/mark.svg だけである。**
#
#     tools/generate-icons.ps1                                   # 本番（apps/karita）
#     tools/generate-icons.ps1 -App example/harness -Accent '#6E7781'   # harness の色違い
#
# **意匠は1つ。色だけを分ける。** 本番と harness は同じ端末に並んで入るので、見分けが
# つかないと「どちらで測ったか」が記録に残らない。マークを別にするのは意匠の決定であり、
# それは仕様側（../karita-ui-probe）が「正式な意匠を決めない」と宣言している場所である。
#
# **-Accent を付けたときはブランド原本（icon.svg・icon-1024.png）を書かない。** 付けたまま
# 走らせると、原本が harness の色に置き換わる。
param(
    # 出力先のプロジェクト（リポジトリ直下からの相対）。
    [string]$App = 'apps/karita',

    # 背景色。既定は Karita v1 の青である。**指定すると派生扱いになる**（原本を書かない）。
    [string]$Accent
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent
$source = Join-Path $root 'assets/branding/karita-icon/v1'
$appDir = Join-Path $root $App
if (-not (Test-Path -LiteralPath $appDir)) { throw "出力先が見つからない: $appDir" }
$res = Join-Path $appDir 'android/app/src/main/res'
$brand = '#245DEB'
$derived = -not [string]::IsNullOrWhiteSpace($Accent)
$accent = if ($derived) { $Accent } else { $brand }
[xml]$svg = Get-Content -LiteralPath (Join-Path $source 'mark.svg') -Raw
$paths = @($svg.svg.g.path | ForEach-Object { $_.d })
$utf8 = [System.Text.UTF8Encoding]::new($false)
function Write-Text($path, $value) {
    [System.IO.Directory]::CreateDirectory((Split-Path $path -Parent)) | Out-Null
    [System.IO.File]::WriteAllText($path, $value + "`n", $utf8)
}
# The master uses absolute M/L/C/Z commands only. Fail on unsupported commands.
function New-MarkPath {
    $shape = [System.Drawing.Drawing2D.GraphicsPath]::new()
    foreach ($data in $paths) {
        $tokens = [regex]::Matches($data, '[A-Za-z]|-?\d+(?:\.\d+)?')
        $i = 0; $x = 0.0; $y = 0.0
        while ($i -lt $tokens.Count) {
            $command = $tokens[$i++].Value
            switch ($command) {
                'M' { $x = [single]$tokens[$i++].Value; $y = [single]$tokens[$i++].Value; $shape.StartFigure() }
                'L' {
                    $nx = [single]$tokens[$i++].Value; $ny = [single]$tokens[$i++].Value
                    $shape.AddLine($x, $y, $nx, $ny); $x = $nx; $y = $ny
                }
                'C' {
                    $a = [single]$tokens[$i++].Value; $b = [single]$tokens[$i++].Value
                    $c = [single]$tokens[$i++].Value; $d = [single]$tokens[$i++].Value
                    $nx = [single]$tokens[$i++].Value; $ny = [single]$tokens[$i++].Value
                    $shape.AddBezier($x, $y, $a, $b, $c, $d, $nx, $ny); $x = $nx; $y = $ny
                }
                'Z' { $shape.CloseFigure() }
                default { throw "Unsupported SVG command: $command" }
            }
        }
    }
    return ,$shape
}
function Render-Icon([int]$size, [bool]$rounded = $true) {
    $hi = [System.Drawing.Bitmap]::new($size * 4, $size * 4)
    $g = [System.Drawing.Graphics]::FromImage($hi)
    $g.SmoothingMode = 'AntiAlias'
    $g.ScaleTransform(($size * 4 / 1024.0), ($size * 4 / 1024.0))
    $brush = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml($accent))
    if ($rounded) {
        $bg = [System.Drawing.Drawing2D.GraphicsPath]::new()
        $bg.AddArc(0, 0, 256, 256, 180, 90)
        $bg.AddArc(768, 0, 256, 256, 270, 90)
        $bg.AddArc(768, 768, 256, 256, 0, 90)
        $bg.AddArc(0, 768, 256, 256, 90, 90)
        $bg.CloseFigure(); $g.FillPath($brush, $bg); $bg.Dispose()
    } else { $g.FillRectangle($brush, 0, 0, 1024, 1024) }
    $shape = New-MarkPath
    $g.FillPath([System.Drawing.Brushes]::White, $shape)
    $shape.Dispose(); $brush.Dispose(); $g.Dispose()
    $bitmap = [System.Drawing.Bitmap]::new($size, $size)
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.DrawImage($hi, 0, 0, $size, $size)
    $g.Dispose(); $hi.Dispose()
    return ,$bitmap
}
# **原本は派生では書き換えない**（上の -Accent の注記）。
if (-not $derived) {
    $svgPaths = ($paths | ForEach-Object { "    <path fill=`"#FFFFFF`" d=`"$_`"/>" }) -join "`n"
    Write-Text (Join-Path $source 'icon.svg') "<svg xmlns=`"http://www.w3.org/2000/svg`" viewBox=`"0 0 1024 1024`">`n  <rect width=`"1024`" height=`"1024`" fill=`"$accent`"/>`n$svgPaths`n</svg>"
    $bitmap = Render-Icon 1024 $false
    $bitmap.Save((Join-Path $source 'icon-1024.png')); $bitmap.Dispose()
}
# PNG-compressed images in one ICO, including small-size entries.
$sizes = @(16,24,32,48,64,128,256)
$blobs = foreach ($size in $sizes) {
    $bitmap = Render-Icon $size
    $stream = [System.IO.MemoryStream]::new()
    $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    ,$stream.ToArray(); $stream.Dispose(); $bitmap.Dispose()
}
$icoPath = Join-Path $appDir 'windows/runner/resources/app_icon.ico'
$writer = [System.IO.BinaryWriter]::new([System.IO.File]::Create($icoPath))
$writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$sizes.Count)
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    $dimension = $sizes[$i] % 256
    $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
    $writer.Write([byte]0); $writer.Write([byte]0)
    $writer.Write([uint16]1); $writer.Write([uint16]32)
    $writer.Write([uint32]$blobs[$i].Length); $writer.Write([uint32]$offset)
    $offset += $blobs[$i].Length
}
foreach ($blob in $blobs) { $writer.Write([byte[]]$blob) }
$writer.Dispose()
foreach ($entry in @(@('mdpi',48),@('hdpi',72),@('xhdpi',96),@('xxhdpi',144),@('xxxhdpi',192))) {
    $bitmap = Render-Icon $entry[1]
    $bitmap.Save((Join-Path $res "mipmap-$($entry[0])/ic_launcher.png")); $bitmap.Dispose()
}
# Entire mark fits inside the central 66dp diameter circle of a 108dp viewport.
# Original max radial distance is < 500; 0.060 scale => < 30dp radius.
$androidPaths = ($paths | ForEach-Object { "    <path android:fillColor=`"#FFFFFF`" android:pathData=`"$_`"/>" }) -join "`n"
$vector = "<vector xmlns:android=`"http://schemas.android.com/apk/res/android`" android:width=`"108dp`" android:height=`"108dp`" android:viewportWidth=`"108`" android:viewportHeight=`"108`">`n  <group android:scaleX=`"0.060`" android:scaleY=`"0.060`" android:translateX=`"23.28`" android:translateY=`"23.28`">`n$androidPaths`n  </group>`n</vector>"
Write-Text (Join-Path $res 'drawable/ic_launcher_foreground.xml') $vector
Write-Text (Join-Path $res 'drawable/ic_launcher_monochrome.xml') $vector
Write-Text (Join-Path $res 'values/icon_colors.xml') "<resources>`n  <color name=`"ic_launcher_background`">$accent</color>`n</resources>"
$adaptive = "<adaptive-icon xmlns:android=`"http://schemas.android.com/apk/res/android`">`n  <background android:drawable=`"@color/ic_launcher_background`"/>`n  <foreground android:drawable=`"@drawable/ic_launcher_foreground`"/>"
Write-Text (Join-Path $res 'mipmap-anydpi-v26/ic_launcher.xml') "$adaptive`n</adaptive-icon>"
Write-Text (Join-Path $res 'mipmap-anydpi-v33/ic_launcher.xml') "$adaptive`n  <monochrome android:drawable=`"@drawable/ic_launcher_monochrome`"/>`n</adaptive-icon>"
$what = if ($derived) { "derived ($accent)" } else { 'brand master' }
Write-Output "Generated Karita v1 launcher resources for $App — $what."
