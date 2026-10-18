package net.getperf.karita.dev

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle

/**
 * 標準共有（`ACTION_SEND` / `text/plain`）の受け口。
 *
 * **`taskAffinity=""` で karita のタスクへ載らない**（manifest）。Notice だけを出すとき背後に
 * メイン画面が見えず、閉じればブラウザーへ戻る。起動側のフラグに依存しなくなるのが狙いである。
 *
 * **URL が1件でなければアプリを起こさない。** 仕様がそう決めており、Notice を出すのは Flutter
 * が動く前なので、**この3つの文言だけは Dart から供給できない**（`strings.xml`。「文言の正本は
 * ui-probe」の唯一の例外である）。
 *
 * **受理規則は書かない。** ISBN もホストも見ない — それは `karita_handoff` の仕事である。
 */
class ShareReceiverActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val text = if (intent?.action == Intent.ACTION_SEND && intent.type == "text/plain") {
            intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        } else {
            null
        }
        val url = Handoff.soleUrl(text)
        if (url == null) {
            notice(reasonFor(text))
            return
        }

        // **再生成では受け直さない。** 同じ配送で id を進めると、Dart 側から見て新しい共有に
        // 見える。
        if (savedInstanceState == null) Inbox.accept(url, SOURCE_SHARE)
        startActivity(
            Intent(this, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                )
            },
        )
        finish()
    }

    private fun reasonFor(text: String?): Int {
        if (text != null && text.length > Handoff.MAX) return R.string.handoff_too_long
        val lines = text.orEmpty().trim().lines().map(String::trim).filter(String::isNotEmpty)
        val withUrl = lines.count { it.contains("://") }
        return if (withUrl > 1) R.string.handoff_multiple_url else R.string.handoff_no_url
    }

    private fun notice(message: Int) {
        AlertDialog.Builder(this)
            .setTitle(R.string.handoff_notice_title)
            .setMessage(message)
            .setPositiveButton(R.string.handoff_notice_close) { _, _ -> finish() }
            .setOnCancelListener { finish() }
            .show()
    }

    companion object {
        const val SOURCE_SHARE = "share"
    }
}
