package com.bityo.securibit

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/*
 * Android 推播（Firebase Cloud Messaging），Dart 端見 lib/features/notifications/push/android_push.dart。
 * 不用 Flutter 的 firebase_core／firebase_messaging（Windows 建置會被拉進 Firebase C++ SDK），
 * 直接用 com.google.firebase:firebase-messaging，經 channel securibit/push 和 Dart 溝通：
 * - Dart → 原生：available（有沒有 google-services.json）、token、permission、requestPermission、openSettings、takeLaunchLink
 * - 原生 → Dart：tokenChanged（換了 token）、opened（App 開著時點了通知）、received（App 在前景時收到）
 * 推播的 notification 由系統在 App 不在前景時直接顯示（頻道是 data 的 category）；App 在前景時系統不顯示，
 * 由 PushMessagingService 自己用同一個頻道顯示。點通知都會打開 MainActivity，intent 帶著 data 的 link（站內路徑）。
 * android/app/google-services.json 不存在時（例如自己建置）Firebase 不會初始化，available 回傳 false，其他方法都安靜地略過。
 */
object Push {
    const val CHANNEL = "securibit/push"
    const val REQUEST_PERMISSION = 7301

    // 推播 data 的欄位（Edge Function push 送出的）；FCM 會原封不動放進點通知時的 intent extras
    private const val EXTRA_LINK = "link"
    private const val EXTRA_ID = "id"
    private const val EXTRA_CATEGORY = "category"
    // 自己在前景顯示的通知加的記號；系統顯示的通知帶的是 google.message_id
    private const val EXTRA_OURS = "securibit_push"
    private const val EXTRA_FCM = "google.message_id"

    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var pendingPermission: MethodChannel.Result? = null

    // 冷啟動時點通知帶進來的連結（Dart 準備好後用 takeLaunchLink 取走）
    private var launchLink: String? = null

    fun attach(activity: Activity, messenger: BinaryMessenger) {
        ensureChannels(activity)
        val channel = MethodChannel(messenger, CHANNEL)
        this.channel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "available" -> result.success(available(activity))
                "token" -> token(activity, result)
                "permission" -> result.success(permission(activity))
                "requestPermission" -> requestPermission(activity, result)
                "openSettings" -> {
                    openSettings(activity)
                    result.success(null)
                }
                "takeLaunchLink" -> {
                    val link = launchLink
                    launchLink = null
                    result.success(link)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        pendingPermission?.success(false)
        pendingPermission = null
    }

    // 有 google-services.json 時 FirebaseInitProvider 會建立預設的 FirebaseApp
    private fun available(context: Context): Boolean =
        try {
            FirebaseApp.getApps(context).isNotEmpty()
        } catch (e: Exception) {
            false
        }

    private fun token(context: Context, result: MethodChannel.Result) {
        if (!available(context)) {
            result.success(null)
            return
        }
        try {
            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                main.post { result.success(if (task.isSuccessful) task.result else null) }
            }
        } catch (e: Exception) {
            result.success(null)
        }
    }

    // granted：可以顯示通知；denied：Android 13 以上沒給權限，或使用者在系統設定把通知關掉
    private fun permission(context: Context): String {
        val enabled = NotificationManagerCompat.from(context).areNotificationsEnabled()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
            return if (granted && enabled) "granted" else "denied"
        }
        return if (enabled) "granted" else "denied"
    }

    // Android 13 以上跳出系統的通知權限；更舊的版本不用要，直接回傳目前是否允許
    private fun requestPermission(activity: Activity, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || permission(activity) == "granted") {
            result.success(permission(activity) == "granted")
            return
        }
        pendingPermission?.success(false)
        pendingPermission = result
        ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_PERMISSION)
    }

    fun onPermissionResult(granted: Boolean) {
        pendingPermission?.success(granted)
        pendingPermission = null
    }

    private fun openSettings(context: Context) {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}"))
        }
        try {
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (e: Exception) {
            // 打不開就算了
        }
    }

    /// 通知頻道：系統、帳戶、功能（和推播 data 的 category 同名）
    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        for ((id, name, description) in listOf(
            Triple("system", "系統", "重要公告、更新與其他公告"),
            Triple("account", "帳戶", "新的登入、加密密碼與管理員對帳號的變更"),
            Triple("feature", "功能", "群組的邀請、成員、身分組與驗證碼的變更"),
        )) {
            val channel = NotificationChannel(id, name, NotificationManager.IMPORTANCE_DEFAULT)
            channel.description = description
            manager.createNotificationChannel(channel)
        }
    }

    /// 點了通知打開 MainActivity：intent 是推播的就取出連結（只接受 / 開頭的站內路徑）。
    /// coldStart：App 剛打開，Dart 還沒準備好，先留著等 takeLaunchLink；否則直接交給 Dart
    fun handleIntent(intent: Intent?, coldStart: Boolean) {
        if (intent == null) return
        if (!intent.hasExtra(EXTRA_OURS) && !intent.hasExtra(EXTRA_FCM)) return
        val link = intent.getStringExtra(EXTRA_LINK)
        // 處理過就拿掉，畫面重建時不會再開一次
        intent.removeExtra(EXTRA_LINK)
        intent.removeExtra(EXTRA_OURS)
        intent.removeExtra(EXTRA_FCM)
        val path = if (link != null && link.startsWith("/") && !link.startsWith("//")) link else ""
        val channel = channel
        if (coldStart || channel == null) {
            launchLink = path
        } else {
            channel.invokeMethod("opened", mapOf("link" to path))
        }
    }

    fun onNewToken(token: String) {
        main.post { channel?.invokeMethod("tokenChanged", mapOf("token" to token)) }
    }

    /// App 在前景時收到：系統不會自己顯示，用同一個頻道顯示，並通知 Dart 重新讀收件匣
    fun onMessage(context: Context, message: RemoteMessage) {
        val data = message.data
        val title = message.notification?.title ?: data["title"] ?: return
        val body = message.notification?.body ?: data["body"] ?: ""
        val category = data[EXTRA_CATEGORY]?.takeIf { it == "system" || it == "account" || it == "feature" } ?: "system"
        val link = data[EXTRA_LINK] ?: ""
        val id = data[EXTRA_ID] ?: message.messageId ?: "$title$body"
        main.post { channel?.invokeMethod("received", mapOf("id" to id, "category" to category, "link" to link)) }

        if (permission(context) != "granted") return
        ensureChannels(context)
        val open = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra(EXTRA_OURS, "1")
            .putExtra(EXTRA_LINK, link)
        val pending = PendingIntent.getActivity(
            context,
            id.hashCode(),
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, category)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(id.hashCode(), notification)
        } catch (e: SecurityException) {
            // 權限剛被收回
        }
    }
}

/// FCM 的服務（AndroidManifest.xml 登記）：token 更新、App 在前景時收到的訊息
class PushMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        Push.onNewToken(token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        Push.onMessage(applicationContext, message)
    }
}
