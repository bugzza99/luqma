package com.luqma.admin

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createAttentionChannel()
    }

    /**
     * The admin being told nobody answered an order.
     *
     * Created in Kotlin rather than from Dart because a channel's sound and importance
     * are fixed the moment it first exists and can never be changed afterwards — so it
     * has to be there before the first message can arrive, which means before Flutter
     * has necessarily started.
     *
     * HIGH importance and it bypasses Do Not Disturb, because this only ever fires when
     * something has already gone wrong: an order reaching `needsAttention` means the
     * merchant's own alarm rang in their kitchen and was missed. There is nobody after
     * the admin. It carries no custom sound — that alarm is the merchant's, and it lives
     * in their APK.
     */
    private fun createAttentionChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(ORDERS_CHANNEL_ID) != null) return

        val channel = NotificationChannel(
            ORDERS_CHANNEL_ID,
            "أوردرات محتاجة تدخّل",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "أوردر عدّى وقته ومحدش ردّ عليه."
            enableVibration(true)
            // Long, uneven pulses. A short buzz reads as a message.
            vibrationPattern = longArrayOf(0, 600, 300, 600)
            setBypassDnd(true)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PRIVATE
        }

        manager.createNotificationChannel(channel)
    }

    companion object {
        /**
         * The same id the merchant's alarm uses, and the same one the trigger writes:
         * this is a critical operational alert, and Android's per-channel controls are
         * what keep somebody who muted marketing from silencing it by accident.
         */
        const val ORDERS_CHANNEL_ID = "orders_critical"
    }
}
