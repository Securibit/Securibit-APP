package com.bityo.securibit

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import java.io.File
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// local_auth 需要 FragmentActivity
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // 預設不允許截圖：在 Flutter 讀到設定之前就先擋住，冷啟動時的多工畫面也不會露出內容
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
        // 點推播通知打開 App（見 Push.kt）；畫面重建（旋轉等）時不是新的點擊
        if (savedInstanceState == null) Push.handleIntent(intent, coldStart = true)
    }

    // App 開著時點了推播通知（launchMode 是 singleTop）
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Push.handleIntent(intent, coldStart = false)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == Push.REQUEST_PERMISSION) {
            Push.onPermissionResult(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        Push.detach()
        super.cleanUpFlutterEngine(flutterEngine)
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

        /*
         * 自動更新（lib/features/update/update_installer.dart 的 AndroidApkInstaller）：
         * selfUpdate → 這個 APK 是不是 GitHub 版（manifest 有 REQUEST_INSTALL_PACKAGES）；Google Play 版回傳 false，整個檢查更新關掉
         * updatesDir → 下載 APK 的資料夾（cacheDir/updates，FileProvider 只分享這裡）
         * canInstall → 使用者允許了「安裝不明應用程式」；openInstallSettings 打開那個設定
         * install → 用 FileProvider 把下載好（已通過檢查碼）的 APK 交給系統的安裝畫面
         */
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "securibit/update").setMethodCallHandler { call, result ->
            when (call.method) {
                "selfUpdate" -> result.success(selfUpdate())
                "updatesDir" -> result.success(File(cacheDir, "updates").apply { mkdirs() }.absolutePath)
                "canInstall" -> result.success(canInstallPackages())
                "openInstallSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")))
                    } else {
                        startActivity(Intent(Settings.ACTION_SECURITY_SETTINGS))
                    }
                    result.success(null)
                }
                "install" -> {
                    val path = call.argument<String>("path")
                    if (path == null || !selfUpdate()) {
                        result.success(false)
                    } else {
                        result.success(installApk(File(path)))
                    }
                }
                else -> result.notImplemented()
            }
        }

        // 推播（Firebase Cloud Messaging，見 Push.kt）
        Push.attach(this, flutterEngine.dartExecutor.binaryMessenger)

        // 已登入的裝置要顯示的裝置名稱（lib/features/profile/session_device.dart）
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "securibit/device").setMethodCallHandler { call, result ->
            when (call.method) {
                "name" -> result.success(deviceName())
                else -> result.notImplemented()
            }
        }
    }

    // manifest 有沒有要求安裝 APK 的權限（只有 GitHub 版合併 src/selfUpdate/AndroidManifest.xml）
    private fun selfUpdate(): Boolean {
        val info = try {
            packageManager.getPackageInfo(packageName, PackageManager.GET_PERMISSIONS)
        } catch (e: PackageManager.NameNotFoundException) {
            return false
        }
        return info.requestedPermissions?.contains(Manifest.permission.REQUEST_INSTALL_PACKAGES) == true
    }

    // Android 8 起每個 App 要個別允許「安裝不明應用程式」；更舊的版本由系統的安裝畫面詢問
    private fun canInstallPackages(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()

    private fun installApk(apk: File): Boolean {
        // 只接受 cacheDir/updates 裡的檔案
        val dir = File(cacheDir, "updates").canonicalFile
        val file = apk.canonicalFile
        if (!file.isFile || !file.path.startsWith(dir.path + File.separator)) return false
        return try {
            val uri = FileProvider.getUriForFile(this, "$packageName.updates", file)
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "application/vnd.android.package-archive")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    // 系統設定裡的裝置名稱（Android 7.1 以上）；沒有時用「廠牌 型號」，例如 Google Pixel 8
    private fun deviceName(): String {
        val named = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
            Settings.Global.getString(contentResolver, Settings.Global.DEVICE_NAME)
        } else {
            null
        }
        if (!named.isNullOrBlank()) return named.trim()
        val maker = Build.MANUFACTURER.orEmpty().replaceFirstChar { it.uppercase() }
        val model = Build.MODEL.orEmpty()
        return if (model.startsWith(maker, ignoreCase = true)) model else "$maker $model".trim()
    }
}
