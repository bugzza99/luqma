package com.luqma.merchant

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createOrderChannel()
    }

    /**
     * The channel a new order arrives on.
     *
     * Created here, in Kotlin, rather than from Dart: a channel's sound and importance
     * are fixed the moment it is first created and can never be changed afterwards —
     * only deleting it and creating a new id does that. So it has to exist before the
     * first message can arrive, which means before Flutter has necessarily started.
     *
     * It is deliberately separate from every other notification this app sends. Android
     * gives the user per-channel controls, so somebody who mutes marketing must not be
     * able to silence this one by accident — that is the whole reason the two categories
     * are split at all.
     *
     * MAX importance, the app's own looping alarm sound, and vibration: this fires in a
     * kitchen, over an extractor fan, at a phone on a shelf across the room.
     */
    private fun createOrderChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(ORDERS_CHANNEL_ID) != null) return

        val channel = NotificationChannel(
            ORDERS_CHANNEL_ID,
            "طلبات جديدة",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "صوت مرتفع لما يوصل طلب جديد. مينفعش يتقفل."
            enableVibration(true)
            // Long, uneven pulses. A short buzz reads as a message.
            vibrationPattern = longArrayOf(0, 600, 300, 600, 300, 600)
            enableLights(true)
            setBypassDnd(true)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            setSound(
                Uri.parse("android.resource://$packageName/raw/new_order"),
                AudioAttributes.Builder()
                    // The alarm stream, not notification: it stays audible on vibrate
                    // and at the volume a person set for being woken up.
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
        }

        manager.createNotificationChannel(channel)
    }

    companion object {
        /**
         * Also named in AndroidManifest.xml as the FCM default channel, so a message
         * that arrives with the app closed lands here rather than on a channel Android
         * invents with default importance and no sound.
         */
        const val ORDERS_CHANNEL_ID = "orders_critical"
    }
}
