import 'package:karita_app/karita_app.dart';

String? syncNotice(AppSyncState state) => switch (state) {
  AppSyncState.signInRequired => '同期が停止しています。再サインインが必要です。',
  AppSyncState.appUpdateRequired => 'アプリの更新が必要です。最新版に更新して、再度開いてください。',
  AppSyncState.needsAttention => 'データを確認できません。詳細を確認してください。',
  _ => null,
};

/// 記録済みのアカウントと違う Google アカウントに接続している旗の文言。
const String accountMismatchNotice =
    '別の Google アカウントに接続しています。同期は停止しました。'
    'この端末のデータは失われていません。';

const themeLabels = {'system': 'システムに合わせる', 'light': 'ライト', 'dark': 'ダーク'};

/// 開くブラウザーの表示名。**値は `device.json` の `browser.app` である。**
const browserLabels = {
  'system': 'システムの既定',
  'edge': 'Edge',
  'chrome': 'Chrome',
  'firefox': 'Firefox',
};
