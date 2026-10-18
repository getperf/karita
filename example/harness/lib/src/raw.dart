/// 生値を並べる部品。**規則1「文言を書かない」を形にしたものである。**
///
/// 出すのは enum 識別子・生値・件数だけで、表示名・アイコン・色・説明文を持たない。表示のための
/// 言い換えはすべて本番 GUI（`../karita-ui-probe`）の仕事であり、ここに書いたものは本番 GUI の
/// 断片である。
///
/// **キーは API の名前そのものにする。** `state` を「状態」と書いた瞬間に、この harness は
/// 「値を見せるもの」から「値を意味づけるもの」になる。
library;

import 'package:flutter/material.dart';

/// 1行の生値。
class RawRow extends StatelessWidget {
  final String name;
  final Object? value;

  const RawRow(this.name, this.value, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 180,
              child: SelectableText(name, style: _mono(context)),
            ),
            Expanded(
              child: SelectableText('${value ?? 'null'}', style: _mono(context)),
            ),
          ],
        ),
      );
}

/// 見出し。**識別子だけを置く。**
class RawHeading extends StatelessWidget {
  final String name;

  const RawHeading(this.name, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: SelectableText(
          name,
          style: _mono(context).copyWith(fontWeight: FontWeight.bold),
        ),
      );
}

/// `Map` をそのまま並べる。**並べ替えない** — 宣言順が意味を持つことがある。
class RawMap extends StatelessWidget {
  final Map<String, Object?> value;

  const RawMap(this.value, {super.key});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in value.entries)
            RawRow(entry.key, entry.value),
        ],
      );
}

/// 行の並び。**件数を必ず出す。** 空と「読めていない」を見分けるためである。
class RawRows extends StatelessWidget {
  final String name;
  final List<Map<String, Object?>> rows;

  const RawRows(this.name, this.rows, {super.key});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RawHeading('$name  n=${rows.length}'),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SelectableText('$row', style: _mono(context)),
            ),
        ],
      );
}

/// 押すと何かが起きるもの。**ラベルは呼ぶ API か CLI の名前そのものにする。**
class RawAction extends StatelessWidget {
  final String name;
  final VoidCallback? onPressed;

  const RawAction(this.name, this.onPressed, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 8),
        child: OutlinedButton(
          onPressed: onPressed,
          child: Text(name, style: _mono(context)),
        ),
      );
}

/// 引数を1つ受ける口。**ラベルは引数名そのものにする。**
class RawField extends StatelessWidget {
  final String name;
  final TextEditingController controller;
  final double width;

  const RawField(this.name, this.controller, {this.width = 200, super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 8),
        child: SizedBox(
          width: width,
          child: TextField(
            controller: controller,
            style: _mono(context),
            decoration: InputDecoration(
              labelText: name,
              labelStyle: _mono(context),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
      );
}

TextStyle _mono(BuildContext context) =>
    const TextStyle(fontFamily: 'monospace', fontSize: 12);
