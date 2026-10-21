package com.bityo.securibit

import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// local_auth 需要 FragmentActivity
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // 預設不允許截圖：在 Flutter 讀到設定之前就先擋住，冷啟動時的多工畫面也不會露出內容
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
    }

    /*
     * 設定頁的「允許截圖」與 App 鎖定（lib/features/settings/screen_privacy.dart）：
     * blockCapture → FLAG_SECURE，擋住截圖、錄影、投放與多工畫面縮圖；
     * hideInSwitcher → Android 13 以上可以只隱藏多工畫面縮圖、不擋截圖。
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "securibit/privacy").setMethodCallHandler { call, result ->
            when (call.method) {
                "configure" -> {
                    val block = call.argument<Boolean>("blockCapture") ?: true
                    val hide = call.argument<Boolean>("hideInSwitcher") ?: true
                    if (block) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        setRecentsScreenshotEnabled(!hide)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
