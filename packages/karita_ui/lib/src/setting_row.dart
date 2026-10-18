/// 設定の1行。**全 feature が使うので `lib/src/` の直下に置く**（`notice.dart` と同じ位置）。
///
/// 形は設定画面の段で決めた（2026-09-17）。
/// **1行目にタイトルと操作、2行目に現在値、3行目に短い説明。狭い画面では操作を折り返す。**
///
/// **2026-09-18 に設定画面から出した。** 図書館管理の詳細が同じ形を欲しがったためで、
/// **写すのではなく共有する** — 操作の置き場が2つの実装に分かれると、片方だけが動く。
///
/// **操作は右端である。** 左に寄せて1つずつ行を使うと、右が空いたまま縦に伸びる。
library;

import 'package:flutter/material.dart';

class KaritaSettingRow extends StatelessWidget {
  const KaritaSettingRow({
    super.key,
    required this.name,
    this.description,
    this.value,
    this.valueWidget,
    this.control,
    this.trailing,
  });

  /// 項目の名前。**左端に出る。**
  final String name;

  /// 短い説明。**無い方が読めるなら置かない。**
  final String? description;

  /// 現在値。**名前の下に出る。**
  final String? value;

  /// 現在値を自分で組みたいとき。[value] と同時には使わない。
  final Widget? valueWidget;

  /// 操作。**右端に出て、狭い画面では次の行へ折り返す。**
  final Widget? control;

  /// 行の下へ足すもの（失敗の帯など）。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(name, style: theme.textTheme.titleSmall),
              if (control != null) control!,
            ],
          ),
          if (value != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(value!),
            ),
          if (valueWidget != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: valueWidget!,
            ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                description!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
