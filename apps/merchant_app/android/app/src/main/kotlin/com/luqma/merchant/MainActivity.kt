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
        createQuietChannel()
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

    /**
     * Everything that is not a new order.
     *
     * The commission reminder and the shop's own billing notices are written into
     * `push_outbox` on the `orders` channel deliberately — the trigger's own comment says
     * an advert can wait and sharing the alarm teaches somebody to ignore it. **This app
     * had no such channel**, so FCM fell back to the id named in AndroidManifest.xml as
     * the default, which is the alarm: the Saturday commission reminder arrived on the
     * alarm stream, bypassing Do Not Disturb, at the volume set for being woken up.
     *
     * The intent was right and the effect was the exact thing it warned against. This
     * channel is what makes the intent true on the phone rather than only in the schema —
     * the same reason the customer app has a separate marketing channel.
     *
     * DEFAULT importance: it makes a sound and appears in the shade, and it does not
     * bypass Do Not Disturb or claim the alarm stream. A merchant who mutes this keeps
     * their new-order alarm, which is the entire point of the split.
     */
    private fun createQuietChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(QUIET_CHANNEL_ID) != null) return

        val channel = NotificationChannel(
            QUIET_CHANNEL_ID,
            "تنبيهات الحساب",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "العمولة والاشتراك وطلبات الإعلانات. مش أوردرات."
        }

        manager.createNotificationChannel(channel)
    }

    companion object {
        /**
         * Also named in AndroidManifest.xml as the FCM default channel, so a message
         * that arrives before this activity has ever run lands here rather than on a
         * channel Android invents with default importance and no sound.
         *
         * That claim was false until 2026-08-31 — the meta-data was never in the
         * manifest — and it stopped being harmless the day messages started carrying a
         * `notification` block, because that is when Android began drawing them itself.
         */
        const val ORDERS_CHANNEL_ID = "orders_critical"

        /**
         * Matches the `orders` value the commission and promotion triggers write into
         * `push_outbox.channel`. Without this channel existing, FCM falls back to the
         * manifest's default — `orders_critical` — and a billing reminder rings the
         * kitchen alarm.
         */
        const val QUIET_CHANNEL_ID = "orders"
    }
}
