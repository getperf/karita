<#
.SYNOPSIS
  karita のログを目視で追う。**読むだけのデバッグ用スクリプトである。**

.DESCRIPTION
  定義は 非公開資料:logging-and-diagnostics.md の「目視で追う」。

  前面 (logs\karita.log)・背面 (logs\karita-background.log)・過渡の背面記録
  (background-runs.jsonl) を末尾から追い、1行1件で出す。text 形式と jsonl 形式の
  どちらの行も受け、jsonl の行は text の並びへ直して出す。

  **集計しない。書き戻さない。** 製品の一部ではないので、配布物にも受入にも入らない。

  データ領域はアプリと同じ順序で解決する。KARITA_HOME があればそれ、次に .env の
  KARITA_SEED があれば %TEMP%\karita-verify（種モード）、無ければ
  %LOCALAPPDATA%\Karita。

.EXAMPLE
  pwsh tools/logtail.ps1

.EXAMPLE
  pwsh tools/logtail.ps1 -Source background -Level WARNING

.EXAMPLE
  pwsh tools/logtail.ps1 -Match 'sync\.run' -Lines 200 -Once

.EXAMPLE
  # 実機から落としてから読む
  adb exec-out run-as <applicationId> cat files/logs/karita.log > C:\tmp\karita\logs\karita.log
  pwsh tools/logtail.ps1 -Home C:\tmp\karita -Once
#>
[CmdletBinding()]
param(
    # データ領域。既定は KARITA_HOME → .env の KARITA_SEED（%TEMP%\karita-verify）→ %LOCALAPPDATA%\Karita。
    [Alias('Home')]
    [string]$KaritaHome,

    # 追うファイル。
    [ValidateSet('front', 'background', 'both')]
    [string]$Source = 'both',

    # この水準以上だけを出す。
    [ValidateSet('ALL', 'FINEST', 'FINER', 'FINE', 'CONFIG', 'INFO', 'WARNING', 'SEVERE', 'SHOUT')]
    [string]$Level = 'ALL',

    # logger と event に掛ける正規表現。
    [string]$Match,

    # 追い始める前に出す末尾の行数。
    [int]$Lines = 50,

    # 既定は追い続ける。-Once を付けると末尾 n 行だけ出して終わる。
    #
    # **真偽値の引数にしない。** `powershell.exe -File` は `-Follow:$false` を文字列のまま渡すので、
    # 5.1 と 7 で書き方が変わってしまう。
    [switch]$Once
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# package:logging の水準。**名前と値をここで1回だけ決める。**
$LevelValue = @{
    ALL = 0; FINEST = 300; FINER = 400; FINE = 500; CONFIG = 700
    INFO = 800; WARNING = 900; SEVERE = 1000; SHOUT = 1200
}
$Threshold = $LevelValue[$Level]

function Resolve-KaritaHome {
    param([string]$Explicit)

    if ($Explicit) { return $Explicit.Trim() }

    if ($env:KARITA_HOME -and $env:KARITA_HOME.Trim()) { return $env:KARITA_HOME.Trim() }

    # **種モードの既定もアプリと同じに解決する**（2026-09-24）。`.env` に `KARITA_SEED` が値付きで
    # あれば、アプリは `%TEMP%\karita-verify` を使う（`seedHome()`）。ここが本番の領域を見ると、
    # 検証中の端末とは別のログを黙って追うことになる。本番を見たいときは -Home で渡す。
    $envFile = Join-Path (Join-Path $PSScriptRoot '..') '.env'
    if ((Test-Path -LiteralPath $envFile) -and $env:TEMP) {
        $seed = [IO.File]::ReadAllLines($envFile) |
            Where-Object { $_ -match '^\s*KARITA_SEED\s*=\s*(\S.*)$' } |
            Select-Object -First 1
        if ($seed) {
            Write-Host '.env に KARITA_SEED があるため、種モードの領域を見ます。' -ForegroundColor Yellow
            return (Join-Path $env:TEMP 'karita-verify')
        }
    }

    if ($env:LOCALAPPDATA -and $env:LOCALAPPDATA.Trim()) {
        return (Join-Path $env:LOCALAPPDATA.Trim() 'Karita')
    }

    # **推測で代わりを立てない。** アプリ側 (WindowsAppPaths.resolve) と同じ判断である。
    throw 'LOCALAPPDATA が無いためデータ領域を決められません。-Home で指定してください。'
}

# 追う対象。**出所の1文字は行頭に出る。**
function Get-Targets {
    param([string]$Root, [string]$Which)

    $all = @(
        [pscustomobject]@{ Tag = 'F'; Path = (Join-Path $Root 'logs\karita.log'); Kind = 'front' }
        [pscustomobject]@{ Tag = 'B'; Path = (Join-Path $Root 'logs\karita-background.log'); Kind = 'background' }
        # 過渡。ログへ吸収されるまでの背面記録。
        [pscustomobject]@{ Tag = 'B'; Path = (Join-Path $Root 'background-runs.jsonl'); Kind = 'background' }
    )

    if ($Which -eq 'both') { return $all }
    return @($all | Where-Object { $_.Kind -eq $Which })
}

# 値を1つ文字列にする。**ConvertFrom-Json は ISO 8601 を DateTime にする**ので、
# 元の並びへ戻す。戻さないと行頭の時刻が土地ごとの書式になり、並べ替えも壊れる。
function Format-Value {
    param($Value)

    if ($Value -is [datetime]) {
        return $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    }
    if ($Value -is [string]) { return $Value }
    return ($Value | ConvertTo-Json -Compress -Depth 6)
}

# jsonl の行を text の並びへ直す。**項目と順序は text 形式の定義に合わせる。**
function ConvertTo-TextLine {
    param([string]$Line)

    try {
        $o = $Line | ConvertFrom-Json
    } catch {
        # **読めない行を捨てない。** 途中で落ちた背面が半端な行を残すのは観測そのものである。
        # 時刻が読めないので、**並べ替えでは末尾へ置く** — 半端な行はファイルの末尾にある。
        return [pscustomobject]@{ At = '9999'; Level = 'SHOUT'; Logger = ''; Event = ''; Text = $Line }
    }

    $props = @($o.PSObject.Properties)
    $known = @('at', 'level', 'logger', 'event', 'error')
    $at = ''; $level = ''; $logger = ''; $ev = ''
    foreach ($p in $props) {
        switch ($p.Name) {
            'at' { $at = Format-Value $p.Value }
            'level' { $level = [string]$p.Value }
            'logger' { $logger = [string]$p.Value }
            'event' { $ev = [string]$p.Value }
        }
    }

    # 背面の過渡記録 (background-runs.jsonl) は level も logger も持たない。
    if (-not $level) { $level = 'INFO' }
    if (-not $ev -and $o.PSObject.Properties.Name -contains 'phase') {
        $ev = 'background.' + [string]$o.phase
        $logger = 'karita.background'
        $known = $known + 'phase'   # event にした値を付随値へ二度出さない
    }

    $pairs = foreach ($p in $props) {
        if ($known -contains $p.Name) { continue }
        $v = $p.Value
        if ($null -eq $v) { continue }
        $s = (Format-Value $v) -replace "`r?`n", '\n'
        if ($s -match '[\s="]') { '{0}="{1}"' -f $p.Name, ($s -replace '([\\"])', '\$1') }
        else { '{0}={1}' -f $p.Name, $s }
    }
    if ($o.PSObject.Properties.Name -contains 'error' -and $o.error) {
        $e = ([string]$o.error) -replace "`r?`n", '\n'
        $pairs = @($pairs) + @('error="{0}"' -f ($e -replace '([\\"])', '\$1'))
    }

    $text = ('{0} {1,-7} {2} {3} {4}' -f $at, $level, $logger, $ev, (@($pairs) -join ' ')).TrimEnd()
    return [pscustomobject]@{ At = $at; Level = $level; Logger = $logger; Event = $ev; Text = $text }
}

# text の行から水準・logger・event を取り出す。**並びは書式の定義どおり。**
function Read-TextLine {
    param([string]$Line)

    $t = $Line -split '\s+', 5
    if ($t.Count -ge 4) {
        return [pscustomobject]@{ At = $t[0]; Level = $t[1]; Logger = $t[2]; Event = $t[3]; Text = $Line }
    }
    return [pscustomobject]@{ At = '9999'; Level = 'SHOUT'; Logger = ''; Event = ''; Text = $Line }
}

function Read-Line {
    param([string]$Line)

    if ($Line.TrimStart().StartsWith('{')) { return ConvertTo-TextLine -Line $Line }
    return Read-TextLine -Line $Line
}

function Test-Wanted {
    param([psobject]$Row)

    $v = if ($LevelValue.ContainsKey($Row.Level)) { $LevelValue[$Row.Level] } else { 1200 }
    if ($v -lt $Threshold) { return $false }
    if ($Match -and -not (($Row.Logger -match $Match) -or ($Row.Event -match $Match))) { return $false }
    return $true
}

function Write-Row {
    param([string]$Tag, [psobject]$Row)

    $color = switch ($Row.Level) {
        'SEVERE' { 'Red' }
        'SHOUT' { 'Red' }
        'WARNING' { 'Yellow' }
        default { 'Gray' }
    }
    Write-Host ('{0} {1}' -f $Tag, $Row.Text) -ForegroundColor $color
}

# 追記だけを読む。**書き手を止めない** — FileShare.ReadWrite で開く。
function Read-Appended {
    param([string]$Path, [long]$From)

    $stream = [System.IO.FileStream]::new(
        $Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
    try {
        [void]$stream.Seek($From, [System.IO.SeekOrigin]::Begin)
        $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
        $text = $reader.ReadToEnd()
        return [pscustomobject]@{ Text = $text; Position = $stream.Position }
    } finally {
        $stream.Dispose()
    }
}

$root = Resolve-KaritaHome -Explicit $KaritaHome
$targets = Get-Targets -Root $root -Which $Source

Write-Host "home: $root" -ForegroundColor Cyan
foreach ($t in $targets) {
    $mark = if (Test-Path -LiteralPath $t.Path) { ' ' } else { '(無し)' }
    Write-Host ('  {0} {1} {2}' -f $t.Tag, $t.Path, $mark) -ForegroundColor DarkGray
}

# 初回。**両方の末尾を時刻で混ぜて出す。** ISO 8601 の UTC なので文字列順で並ぶ。
$state = @{}
$initial = New-Object System.Collections.ArrayList
foreach ($t in $targets) {
    $state[$t.Path] = 0L
    if (-not (Test-Path -LiteralPath $t.Path)) { continue }
    $content = Read-Appended -Path $t.Path -From 0
    $state[$t.Path] = $content.Position
    $tail = @($content.Text -split "`r?`n" | Where-Object { $_.Trim() }) | Select-Object -Last $Lines
    foreach ($line in $tail) {
        $row = Read-Line -Line $line
        if (Test-Wanted -Row $row) {
            [void]$initial.Add([pscustomobject]@{ Tag = $t.Tag; Row = $row })
        }
    }
}
foreach ($item in ($initial | Sort-Object { $_.Row.At })) {
    Write-Row -Tag $item.Tag -Row $item.Row
}

if ($Once) { return }

Write-Host '--- 追跡中。Ctrl+C で止める ---' -ForegroundColor Cyan
while ($true) {
    foreach ($t in $targets) {
        if (-not (Test-Path -LiteralPath $t.Path)) { continue }
        $length = (Get-Item -LiteralPath $t.Path).Length
        # 回転・置換で短くなったら先頭から読み直す。**追従はここまでしかしない。**
        if ($length -lt $state[$t.Path]) { $state[$t.Path] = 0L }
        if ($length -eq $state[$t.Path]) { continue }

        $content = Read-Appended -Path $t.Path -From $state[$t.Path]
        $state[$t.Path] = $content.Position
        foreach ($line in ($content.Text -split "`r?`n")) {
            if (-not $line.Trim()) { continue }
            $row = Read-Line -Line $line
            if (Test-Wanted -Row $row) { Write-Row -Tag $t.Tag -Row $row }
        }
    }
    Start-Sleep -Milliseconds 500
}
