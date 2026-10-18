# 「karita をはじめる」を何度でも再現するための使い捨て環境。
#
#     tools/first-run-env.ps1 -Action status                 # 端末 a の領域の状態を見る
#     tools/first-run-env.ps1 -Action reset                  # 端末 a を初期インストール前に戻す
#     tools/first-run-env.ps1 -Action run                    # 端末 a として release 版を起動する（ガイド撮影用）
#     tools/first-run-env.ps1 -Action run -Device b          # 端末 b（2台目）として起動する
#     tools/first-run-env.ps1 -Action whoami                 # 端末 a が繋いでいるアカウント
#     tools/first-run-env.ps1 -Action purge-drive -Account <検証用>        # 数えるだけ
#     tools/first-run-env.ps1 -Action purge-drive -Account <検証用> -Yes   # Drive を空にする
#
# **初期化の対象は3層で、別々に戻す。**
#
# | 層 | 中身 | 戻し方 |
# |---|---|---|
# | ローカル | 台帳・token・設定・ログ | `-Action reset`（領域を消して資格情報だけ置き直す） |
# | Drive | 検証用アカウントの `appDataFolder` | `-Action purge-drive`（接続先が `-Account` と一致するときだけ） |
# | 複数端末 | 端末ごとの台帳 | `-Device a` / `-Device b` で領域を分ける |
#
# **本番の領域には触れない。** 既定の `%LOCALAPPDATA%\Karita` とパッケージ専用領域
# （`%LOCALAPPDATA%\Packages\`）を指す領域は、作る前に止める。消すのは目印
# （`.karita-disposable`）を置いた領域だけである。
#
# **Drive を守るのはアカウントの一致である。** `KARITA_HOME` はローカルしか分けない。本番の
# アカウントでサインインした領域で掃除すると、全端末の記録の起点が消える
# （`非公開資料:p5b-verification-mode.md`「注意」）。サインインでは必ず検証用の
# アカウントを選ぶ。
#
# **起動の前に、動いている karita を閉じる。** 単一インスタンスのため、別の karita（Store 版・
# テスト MSIX・開発版）が動いていると、起動は既存の窓へ転送されて終わる。端末 a と b も
# 同時には起動できない — 順に起動して「既存の端末がある」状態を作る。
#
# → 非公開資料:p5c-windows-store.md「2b. 「karita をはじめる」から再現できる環境」

[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('status', 'reset', 'run', 'whoami', 'purge-drive')]
    [string]$Action,

    # 端末の名前。領域は `<Root>\<Device>` になる。
    [ValidatePattern('^[a-z0-9-]+$')]
    [string]$Device = 'a',

    # 使い捨て領域の置き場。**OS の一時領域の下を既定にする** — 消えても困らないものだけを置く。
    [string]$Root = (Join-Path $env:TEMP 'karita-first-run'),

    # 置き直す Desktop の資格情報。**このファイル1つだけを写す**（ディレクトリごと写さない —
    # Android・gateway 用の資格情報まで使い捨て領域へ広げない）。
    [string]$Credentials = (Join-Path $env:LOCALAPPDATA 'Karita\credentials\karita-core-desktop.json'),

    # `purge-drive` で、接続先がこのアカウントであることを確かめる。**既定値を持たない。**
    [string]$Account,

    # `purge-drive` で実際に消す。無ければ数えるだけ。
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$marker = '.karita-disposable'

function Test-Under([string]$path, [string]$parent) {
    # **区切りを付けて比べる。** 付けないと `...\Local\Karita` が `...\Local\KaritaX` に当たる。
    $p = [IO.Path]::GetFullPath($path).TrimEnd('\') + '\'
    $q = [IO.Path]::GetFullPath($parent).TrimEnd('\') + '\'
    return $p.StartsWith($q, [StringComparison]::OrdinalIgnoreCase)
}

$rootFull = [IO.Path]::GetFullPath($Root)
$home_ = Join-Path $rootFull $Device

foreach ($protected in @(
        (Join-Path $env:LOCALAPPDATA 'Karita'),
        (Join-Path $env:LOCALAPPDATA 'Packages'))) {
    if ((Test-Under $rootFull $protected) -or (Test-Under $protected $rootFull)) {
        throw "本番の領域と重なる場所は使えません: $rootFull（$protected）"
    }
}

function Invoke-WithHome([scriptblock]$body) {
    # **元へ戻す。** 呼んだ側のセッションへ `KARITA_HOME` を漏らさない（`run-dev.ps1` と同じ）。
    $previous = $env:KARITA_HOME
    $env:KARITA_HOME = $home_
    try { & $body } finally {
        if ($null -eq $previous) { Remove-Item Env:\KARITA_HOME -ErrorAction SilentlyContinue }
        else { $env:KARITA_HOME = $previous }
    }
}

function Invoke-DriveProbe([string[]]$arguments) {
    if (-not (Test-Path -LiteralPath (Join-Path $home_ 'token.json'))) {
        throw "端末 $Device はまだサインインしていません。-Action run で起動し、検証用のアカウントでサインインしてください。"
    }
    Invoke-WithHome {
        Push-Location (Join-Path $repo 'tools\drive_probe')
        try {
            & dart run bin/drive_probe.dart @arguments
            if ($LASTEXITCODE -ne 0) { throw "drive_probe が $LASTEXITCODE で終わった" }
        } finally { Pop-Location }
    }
}

switch ($Action) {
    'status' {
        Write-Host "home:        $home_"
        if (-not (Test-Path -LiteralPath $home_)) { Write-Host '状態:        未作成（-Action reset で作る）'; return }
        $exists = { param($rel) if (Test-Path -LiteralPath (Join-Path $home_ $rel)) { 'あり' } else { 'なし' } }
        Write-Host ("目印:        " + (& $exists $marker))
        Write-Host ("資格情報:    " + (& $exists 'credentials\karita-core-desktop.json'))
        Write-Host ("token:       " + (& $exists 'token.json'))
        Write-Host ("台帳:        " + (& $exists 'library.db'))
    }

    'reset' {
        if (Test-Path -LiteralPath $home_) {
            # **目印の無い場所は消さない。** 手で作った別の領域を巻き込まない。
            if (-not (Test-Path -LiteralPath (Join-Path $home_ $marker))) {
                throw "目印 $marker が無いので消しません: $home_"
            }
            Remove-Item -LiteralPath $home_ -Recurse -Force
        }
        if (-not (Test-Path -LiteralPath $Credentials)) {
            throw "Desktop の資格情報が見つかりません: $Credentials（-Credentials で指定）"
        }
        $credentialsDir = Join-Path $home_ 'credentials'
        New-Item -ItemType Directory -Force -Path $credentialsDir | Out-Null
        Set-Content -LiteralPath (Join-Path $home_ $marker) -Value 'karita first-run disposable home' -Encoding utf8
        Copy-Item -LiteralPath $Credentials -Destination (Join-Path $credentialsDir 'karita-core-desktop.json')
        Write-Host "端末 $Device を初期インストール前の状態にしました: $home_"
        Write-Host 'Drive は戻していません。必要なら -Action purge-drive を使います。'
    }

    'run' {
        if (-not (Test-Path -LiteralPath (Join-Path $home_ $marker))) {
            throw "端末 $Device の領域がありません。先に -Action reset を実行してください。"
        }
        $running = Get-Process -Name 'karita' -ErrorAction SilentlyContinue
        if ($running) {
            throw "karita が動いています（PID $($running.Id -join ', ')）。閉じてから起動してください — 動いたままだと既存の窓へ転送されます。"
        }
        Write-Host 'サインインでは検証用のアカウントを選んでください。'
        & (Join-Path $PSScriptRoot 'run-dev.ps1') -KaritaHome $home_ --release
    }

    'whoami' { Invoke-DriveProbe @('whoami') }

    'purge-drive' {
        if ([string]::IsNullOrWhiteSpace($Account)) {
            throw '-Account に検証用のアカウントを指定してください。'
        }
        $arguments = @('purge', '--account', $Account.Trim())
        if ($Yes) { $arguments += '--yes' }
        Invoke-DriveProbe $arguments
    }
}
