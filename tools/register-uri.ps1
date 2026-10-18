# `karita://` を HKCU へ登録する。**管理者権限は要らない。**
#
# 配送の形は `karita://share?url=<percent-encoded absolute https URL>` である。操作名も版も
# 作らず、渡すのは URL だけである（非公開資料:browser-handoff-implementation.md 決定 C）。
#
# **受け入れた穴がある。** HKCU に登録した URI スキームは、拡張だけでなく任意の Web ページが
# `location.href` で叩ける。仕様が「入力を信頼済みとみなさない」「共有では業務状態を変えない」
# 「保存は明示確定」と決めているので候補表示までで止まるが、**前面化されること自体は防げない。**
# 閉じられるのは native messaging だけで、それは拡張 ID が固定される（ストア配布）まで取れない。
# MSIX Share Target へ移れば、この穴ごと消える。
#
# 解除は tools/unregister-uri.ps1。
# **登録できる exe は1つだけである。** HKCU の1つの鍵が1本の実行ファイルを指す。既定は本番
# （`apps/karita`）で、harness で受信を測るときだけ `-ExePath` で一時的に向け替える
# （2026-09-23。器ができて harness と本番が同じ機械に並んだ）。
#
# **既定は Debug ビルドである**（2026-09-23 に Release から変えた）。ここが要求するのは
# 「起動できる exe が1本あること」だけで、**ビルド種別に依存する仕組みは何も無い** — 登録は
# パス1本、転送は窓名の一致、受信は `app_links` である。P5a の実機確認が Release で取れたのは
# その時の都合で、**今後の運用は `flutter build --debug` である**（種のガードと同じ線。
# 非公開資料:p5b-verification-mode.md）。Release を測るときは `-ExePath` で指す。
param(
    [string]$ExePath = (Join-Path $PSScriptRoot '..\apps\karita\build\windows\x64\runner\Debug\karita.exe')
)
$ErrorActionPreference = 'Stop'

$exe = (Resolve-Path -LiteralPath $ExePath).Path
if ([IO.Path]::GetExtension($exe) -ne '.exe') { throw '実行ファイルを指定してください。' }

$key = 'HKCU:\Software\Classes\karita'
$command = '"' + $exe + '" "%1"'

if (Test-Path -LiteralPath "$key\shell\open\command") {
    $existing = (Get-Item -LiteralPath "$key\shell\open\command").GetValue('')
    if ($existing -ne $command) {
        # **黙って上書きしない。** 本番ビルドと harness が同じ scheme を取り合う状況は、
        # 「どのビルドが受信したか」を実機で記録する対象そのものである。
        Write-Warning "既存の登録: $existing"
    }
}

New-Item -Path "$key\shell\open\command" -Force | Out-Null
Set-Item -LiteralPath $key -Value 'URL:karita'
New-ItemProperty -LiteralPath $key -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null
Set-Item -LiteralPath "$key\shell\open\command" -Value $command

Write-Output "登録しました: $command"
