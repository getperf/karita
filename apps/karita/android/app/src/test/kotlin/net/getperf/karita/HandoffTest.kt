package net.getperf.karita

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * **Kotlin 側が見るのは「URL がちょうど1件か」だけである**ことを固定する。
 *
 * ここへ受理規則が漏れると、1つ直すのに3箇所と3つの試験が要る形へ戻る。ISBN の規則は
 * `karita_handoff`（純 Dart）にしか無い。
 */
class HandoffTest {
    private val book = "https://calil.jp/book/427421933X"

    @Test
    fun `URL 単独を受ける`() {
        assertEquals(book, Handoff.soleUrl(book))
        assertEquals(book, Handoff.soleUrl("  $book  "))
    }

    @Test
    fun `別行のタイトル付きを受ける`() {
        assertEquals(book, Handoff.soleUrl("達人プログラマー\n$book"))
    }

    @Test
    fun `0件と2件以上は受けない`() {
        assertNull(Handoff.soleUrl(null))
        assertNull(Handoff.soleUrl(""))
        assertNull(Handoff.soleUrl("カーリルで見つけた本"))
        assertNull(Handoff.soleUrl("$book\nhttps://example.jp"))
    }

    @Test
    fun `同じ行に説明文が付いたものは受けない`() {
        assertNull(Handoff.soleUrl("読みたい $book"))
        assertNull(Handoff.soleUrl("$book https://example.jp"))
    }

    @Test
    fun `長すぎる入力は受けない`() {
        assertNull(Handoff.soleUrl("a".repeat(Handoff.MAX + 1)))
    }

    @Test
    fun `書籍かどうかは見ない`() {
        // **ここで分類しない。** カーリルの検索結果も館のサイトも、URL が1件なら通す。
        val search = "https://calil.jp/search?q=x"
        assertEquals(search, Handoff.soleUrl(search))
        val library = "https://www.koto-lib.tokyo.jp/"
        assertEquals(library, Handoff.soleUrl(library))
    }

    @Test
    fun `ISBN が不正でも通す。断るのは Dart 側である`() {
        val invalid = "https://calil.jp/book/4274219330"
        assertEquals(invalid, Handoff.soleUrl(invalid))
    }
}
