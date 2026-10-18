# 開発用 harness

本番と同じ合成層を使う動作確認アプリです。画面・同期の試験や demo_sql_probe.dart の確認に使います。
Android application ID は本番と異なりますが、Windows の既定データ領域は本番と共通です。
本番と同じデータ領域で同時起動せず、専用の KaritaHome を指定してください。

```powershell
tools/run-dev.ps1 -Project example/harness -KaritaHome <専用の絶対パス>
```

[開発手順](../../docs/development.md)
