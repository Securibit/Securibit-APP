package com.bityo.securibit

import android.app.Activity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.fragment.app.FragmentActivity
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.UpdateAvailability
import io.flutter.plugin.common.MethodChannel

/*
 * Google Play 版的強制更新（lib/features/update/play_update.dart）：版本低於後台的最低版本時，
 * 用 Play 的 App 內更新（立即更新）蓋上 Google Play 的「有可用的更新」畫面，由商店下載、安裝並重新開啟 App。
 * GitHub 版自己下載 APK，不走這裡。
 * 結果回傳給 Dart：
 * - unavailable：Google Play 還不知道有新版（剛上架時要等商店更新）或不是從 Google Play 安裝的
 * - canceled：使用者關掉了 Google Play 的畫面
 * - failed：查詢或開啟失敗
 * - ok：Play 開始安裝（通常 App 會直接被重新開啟，不一定收得到）
 */
class PlayUpdate(private val activity: FragmentActivity) {
    private var pending: MethodChannel.Result? = null

    // 要在 onCreate 註冊（Activity STARTED 之前）
    private val launcher: ActivityResultLauncher<IntentSenderRequest> =
        activity.registerForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { res ->
            finish(
                when (res.resultCode) {
                    Activity.RESULT_OK -> "ok"
                    Activity.RESULT_CANCELED -> "canceled"
                    else -> "failed"
                }
            )
        }

    fun start(result: MethodChannel.Result) {
        if (pending != null) {
            result.success("failed")
            return
        }
        pending = result
        val manager = AppUpdateManagerFactory.create(activity)
        manager.appUpdateInfo
            .addOnSuccessListener { info ->
                val availability = info.updateAvailability()
                // 上次的立即更新還沒裝完（例如中途切出去）也要接著顯示
                val resume = availability == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS
                val available = availability == UpdateAvailability.UPDATE_AVAILABLE && info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE)
                if (!resume && !available) {
                    finish("unavailable")
                    return@addOnSuccessListener
                }
                try {
                    if (!manager.startUpdateFlowForResult(info, launcher, AppUpdateOptions.defaultOptions(AppUpdateType.IMMEDIATE))) {
                        finish("unavailable")
                    }
                } catch (e: Exception) {
                    finish("failed")
                }
            }
            .addOnFailureListener { finish("failed") }
    }

    private fun finish(outcome: String) {
        val result = pending ?: return
        pending = null
        result.success(outcome)
    }
}
