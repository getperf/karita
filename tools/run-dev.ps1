# 開発起動。**リポジトリ直下の `.env` を `--dart-define-from-file` でビルドへ渡す。**
#
#     tools/run-dev.ps1                          # Windows で本番アプリを起動する
#     tools/run-dev.ps1 -Device <android-id>     # Android の実機で起動する
#     tools/run-dev.ps1 -ShowDefines             # 渡すものを見るだけ。flutter を呼ばない
#     tools/run-dev.ps1 -Project example/harness # harness を起こす
#     tools/run-dev.ps1 -KaritaHome D:\karita-verify   # home を明示する（種モードの既定を上書き）
#     tools/run-dev.ps1 --dart-define=KARITA_DEMO=memory   # 一回きりの上書き（.env より強い）
#
# **ファイル全体を渡す。** 項目の許可一覧は役目を終えた（2026-09-22）— `--dart-define-from-file`
# は選り分けられないためで、**代わりに「`.env` に秘密を書かない」を規則にする。** このリポジトリ
# では資格情報の置き場が `KARITA_HOME/credentials/` と決まっており、`.env` に秘密が来る構造に
# なっていない。
# → 非公開資料:settings-and-parameters.md#ビルド入力2026-09-22決定
#
# **`.env` をアプリの asset にしない。** アセットに焼くとファイル全体が配布物に入り、組み込む
# 範囲を絞れない。実行時読み込み（`flutter_dotenv` 等）も採らない — 値の解決経路が
# `String.fromEnvironment` と2系統になる。
#
# **値の正否はここで決めない。** `KARITA_DEMO` が `off` / `memory` / `temp` のどれかであることも、
# 種のガードも、合成層（`packages/karita_app`）が起動時に見て落とす。ここに2つ目の表を作ると、
# 片方だけが直ったときに「通るはずの値が通らない」が起きる。
#
# **空の値を `.env` に書かない。** `--dart-define-from-file` は空の値もそのまま渡す。読み手は
# 空文字を「未指定」として扱うが、要らない項目は行ごと消すのが雛形の規則である。
#
# **`--dart-define` の値はプロセスの起動引数に載る。** 同じ機械の他の利用者からは見える。
# 開発機の前提で受け入れており、配布物からキーを取り出せる前提と同じ線である。
# → 非公開資料:external-data-access.md#キー供給2026-09-15決定

# **位置引数を持たない。** 持つと `--dart-define=…` のような「PowerShell の引数に見えない
# トークン」が `$Rest` ではなく位置で束縛され、`-Mode` の ValidateSet に当たって落ちる
# （2026-09-23 に実機で踏んだ）。この script の引数は全部名前で渡す。
[CmdletBinding(PositionalBinding = $false)]
param(
    # `flutter run -d` に渡すもの。`flutter devices` の id。
    [string]$Device = 'windows',

    # `run` は起動、`build` は生成だけ。
    [ValidateSet('run', 'build')][string]$Mode = 'run',

    # 起こすプロジェクト。**既定は本番アプリである**（2026-09-23。器が出来た）。
    # harness は `-Project example/harness` と明示して起こす。
    [string]$Project = 'apps/karita',

    # `KARITA_HOME` をこの起動にだけ効かせる。**`.env` には書けない** — これは
    # `--dart-define` ではなく環境変数で、台帳・設定・秘密・ログの置き場所そのものである。
    #
    # **種モードでは要らない**（2026-09-23）。`KARITA_SEED` が立っている起動は、明示が無ければ
    # **OS の一時領域の下の専用の場所**（`%TEMP%\karita-verify`）を既定にする。ここで渡すのは
    # その既定を上書きしたいときだけである。
    #
    # **手で `$env:KARITA_HOME=…` と打たないこと。** PowerShell のセッションに残り、消し忘れた
    # まま次に本番を起こすと黙って別の home で動く。**値が嘘になるだけで失敗しないので
    # 気づけない。** ここで渡せば、この flutter の呼び出しが終わった時点で元へ戻る。
    # → 非公開資料:p5b-verification-mode.md
    [string]$KaritaHome,

    # `flutter run --target`。probe を起こすときに使う。
    [string]$Target,

    # 渡すものを表示して終わる。**flutter を呼ばない。**
    [switch]$ShowDefines,

    # 残りはそのまま flutter へ渡す。**一回きりの上書きはここでやる** —
    #     tools/run-dev.ps1 --dart-define=KARITA_DEMO=memory
    # 同じ鍵なら `--dart-define` が `--dart-define-from-file` より強い（flutter の仕様）。
    # **項目ごとの引数を script が持たない** — 持つと `.env` と2つの表ができる。
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Rest
)

$ErrorActionPreference = 'Stop'

$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$envFile = Join-Path $repo '.env'
$projectDir = Join-Path $repo $Project

# **値を表示しない項目。** 伏せるのは画面とログだけで、秘匿の手段ではない。
$secret = @('KARITA_CALIL_APPKEY')

if (-not (Test-Path -LiteralPath $projectDir)) {
    throw "起動対象が見つからない: $projectDir"
}

# --- 渡すものを見せる ------------------------------------------------------
# **読むのは表示のためだけである。** ビルドが読むのは `.env` そのもので、この解析結果ではない。
$hasEnv = Test-Path -LiteralPath $envFile
if ($hasEnv) {
    Write-Host "--dart-define-from-file: $envFile"
    foreach ($line in [IO.File]::ReadAllLines($envFile)) {
        $trimmed = $line.Trim()
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) { continue }
        $separator = $trimmed.IndexOf('=')
        if ($separator -le 0) { continue }
        $key = $trimmed.Substring(0, $separator).Trim()
        $value = $trimmed.Substring($separator + 1).Trim()
        $shown = if ($secret -contains $key) { '(伏せる。長さ ' + $value.Length + ')' } else { $value }
        Write-Host ("  {0} = {1}" -f $key, $shown)
    }
} else {
    Write-Host ".env が無い。アプリの既定で起動する（雛形は .env.example）。"
}

# **一回きりの上書きも見せる。** 上の表だけ出すと、実際に効く値と食い違ったまま起動する
# （同じ鍵なら `--dart-define` が `--dart-define-from-file` より強い）。
if ($Rest) {
    Write-Host "そのまま flutter へ渡す（同じ鍵ならファイルより強い）:"
    foreach ($argument in $Rest) {
        # **裸のトークンは、ほぼ位置引数の書き間違いである。** 位置束縛を切ったので、
        # `tools/run-dev.ps1 windows` は flutter の `--target` の相手として渡り、
        # 「Target file "windows" not found」という遠い場所の文言で落ちる。
        if (-not $argument.StartsWith('-')) {
            Write-Warning "「$argument」はそのまま flutter へ渡る。この script の値は名前で渡す（例: -Device windows）。"
        }
        $shown = $argument
        foreach ($key in $secret) {
            if ($argument -match "^(.*$key=)(.*)$") {
                $shown = $Matches[1] + '(伏せる。長さ ' + $Matches[2].Length + ')'
            }
        }
        Write-Host "  $shown"
    }
}

# **`KARITA_HOME` は `--dart-define` ではない。** 上の表には出ないので、別に1行出す。
$hasHome = -not [string]::IsNullOrWhiteSpace($KaritaHome)
if ($hasHome) {
    Write-Host "KARITA_HOME: $KaritaHome  (この起動のあいだだけ)"
} elseif ($env:KARITA_HOME) {
    # **セッションに残っている値を黙って使わない。** 消し忘れは検証用の home で本番を起こす。
    Write-Warning "セッションの KARITA_HOME が効く: $env:KARITA_HOME"
}
if ($ShowDefines) { return }

# --- flutter を呼ぶ --------------------------------------------------------
$arguments = @()
if ($Mode -eq 'run') {
    $arguments += @('run', '-d', $Device)
} else {
    # `build` の相手は端末の id ではなく、作るものの名前である（windows / apk / …）。
    $arguments += @('build', $Device, '--debug')
}
if (-not [string]::IsNullOrWhiteSpace($Target)) {
    $arguments += @('--target', $Target)
}
if ($hasEnv) {
    $arguments += "--dart-define-from-file=$envFile"
}
# **後ろに置く。** 同じ鍵なら `--dart-define` がファイルより強い。
if ($Rest) { $arguments += $Rest }

# **元へ戻す。** 呼んだ側のセッションへ漏らさない（`$null` に戻すのと空文字は別である）。
$previousHome = $env:KARITA_HOME
if ($hasHome) { $env:KARITA_HOME = $KaritaHome }

Push-Location $projectDir
try {
    & flutter @arguments
    if ($LASTEXITCODE -ne 0) { throw "flutter が $LASTEXITCODE で終わった" }
} finally {
    if ($hasHome) {
        if ($null -eq $previousHome) {
            Remove-Item Env:\KARITA_HOME -ErrorAction SilentlyContinue
        } else {
            $env:KARITA_HOME = $previousHome
        }
    }
    Pop-Location
}
