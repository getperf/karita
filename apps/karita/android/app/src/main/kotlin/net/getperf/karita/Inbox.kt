package net.getperf.karita

/**
 * 未処理配送を順に保持する。snapshotは既存利用側向けの最新1件。
 *
 * **単調増加の id を持つ。** 件数では「同じ配送の再処理」（画面の再生成）と「意図した再共有」
 * （同じ URL をもう一度送った）を区別できない。
 *
 * **Dart は取りに行く。** push にすると Flutter が起きる前の配送を落とす — 共有から起動された
 * 直後がまさにその場面である。したがって、**読むことで id は進まない。**
 *
 * プロセスの中だけに持つ。永続化も閲覧履歴化もしない（受け渡し仕様 §3）。
 */
object Inbox {
    private var seq = 0L
    private var pending: Map<String, Any?>? = null
    private val queue = mutableListOf<Map<String, Any?>>()

    @Synchronized
    fun accept(url: String, source: String) {
        seq += 1
        pending = mapOf("id" to seq, "url" to url, "source" to source)
        queue.add(pending!!)
    }

    /** 最新の1件。無ければ `id = 0`（「まだ何も来ていない」）。 */
    @Synchronized
    fun snapshot(): Map<String, Any?> = pending ?: mapOf("id" to 0L)

    @Synchronized
    fun after(id: Long): List<Map<String, Any?>> {
        queue.removeAll { (it["id"] as Long) <= id }
        return queue.toList()
    }
}
