package net.getperf.karita.dev

/**
 * 受け取ったテキストから URL を1件だけ取り出す。
 *
 * **受理規則をここに書かない。** ISBN の規則もホストの判定も `karita_handoff`（純 Dart）に
 * 1箇所だけ置くと決めた（docs/architecture/browser-handoff-implementation.md 決定 A・D）。
 * spike では同じ規則が Dart・JS・Kotlin の3写しになり、1つ直すのに3箇所と3つの試験が要った。
 *
 * ここで止めるのは「URL がちょうど1件あるか」だけである。0件・2件以上・同じ行に説明文が
 * 付いたものは、**アプリを起こさずに** Notice で返す（仕様がそう決めている）。
 *
 * **Dart 側の判定はこれより厳しい。** 揃わないときは Dart が断る側へ倒れるので、
 * 「Kotlin が通したものを Dart が断る」で済む。逆（Kotlin が断って Dart が通す）は起きない。
 */
object Handoff {
    /** 共有テキストの上限。Dart 側の `maxInputLength` と同じ値である。 */
    const val MAX = 4096

    fun soleUrl(text: String?): String? {
        if (text == null || text.length > MAX) return null
        val lines = text.trim().lines().map(String::trim).filter(String::isNotEmpty)
        // 行まるごとが URL のものだけを数える。「説明文 https://…」は拒否する。
        val urls = lines.filter {
            (it.startsWith("https://") || it.startsWith("http://")) && !it.any(Char::isWhitespace)
        }
        return urls.singleOrNull()
    }
}
