package net.getperf.karita

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * **`karita/share` の `snapshot` に答えるだけである。**
 *
 * Dart は取りに行く（pull）。読んでも [Inbox] の id は進まないので、同じ配送を二度処理しない
 * 判断は番号を持つ Dart 側（`HandoffQueue`）が行う。
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "snapshot" -> result.success(Inbox.snapshot())
                    "pending" -> result.success(Inbox.after(call.argument<Number>("after")?.toLong() ?: 0L))
                    else -> result.notImplemented()
                }
            }
    }

    companion object {
        /** Dart 側の `shareChannelName` と同じ値である。 */
        const val CHANNEL = "karita/share"
    }
}
