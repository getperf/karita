# `karita://` の HKCU 登録を外す。
#
# **実機確認の後始末に要る。** harness と本番ビルドを同じ端末へ置いたとき、どちらが受信するかは
# 保証しない（非公開資料:demo-mode.md）。外してから登録し直すことで、どのビルドが受けて
# いるかを確かめられる。
$ErrorActionPreference = 'Stop'

$key = 'HKCU:\Software\Classes\karita'
if (-not (Test-Path -LiteralPath $key)) {
    Write-Output '登録はありません。'
    return
}
$existing = (Get-Item -LiteralPath "$key\shell\open\command" -ErrorAction SilentlyContinue)?.GetValue('')
Remove-Item -LiteralPath $key -Recurse -Force
Write-Output "外しました: $existing"
