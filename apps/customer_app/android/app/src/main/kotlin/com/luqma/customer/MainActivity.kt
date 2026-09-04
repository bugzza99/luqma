package com.luqma.customer

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createOrdersChannel()
        createMarketingChannel()
    }

    /**
     * Where the customer is told what happened to their order.
     *
     * Created here in Kotlin rather than from Dart, for the same reason the merchant's
     * alarm is: a channel's sound and importance are fixed the moment it is first
     * created and can never be changed afterwards — only deleting the id and making a
     * new one does that. So it has to exist before the first message can arrive, which
     * means before Flutter has necessarily started.
     *
     * Deliberately **not** the merchant's channel. That one is MAX importance, bypasses
     * Do Not Disturb, and plays a looping alarm on the alarm stream, because it fires in
     * a kitchen at a phone on a shelf across the room and an unanswered order is money
     * gone. Waking a customer that way to say their food has left the shop is how
     * somebody turns this app's notifications off — and the three messages that reach
     * them here are the ones worth having.
     *
     * DEFAULT importance: it makes a sound and appears, and it does not take over the
     * screen.
     */
    private fun createOrdersChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(ORDERS_CHANNEL_ID) != null) return

        val channel = NotificationChannel(
            ORDERS_CHANNEL_ID,
            "حالة الأوردر",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "لما المطعم يقبل طلبك أو الأوردر يخرج للتوصيل."
            enableVibration(true)
        }

        manager.createNotificationChannel(channel)
    }

    /**
     * The offers, and the reason they are a channel of their own.
     *
     * `users.marketing_push` is the switch inside the app, and it is the one the server
     * honours — but a customer who is tired of the advertising will reach for the phone's
     * own notification settings long before they go looking through حسابي. If offers and
     * order updates shared a channel, silencing the first would silence the second, and
     * somebody would stop being told where their food is because they turned off an ad.
     *
     * LOW importance: it appears in the shade without a sound. An offer is not worth
     * interrupting anybody for, and one that does is one that gets the whole app muted.
     */
    private fun createMarketingChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(MARKETING_CHANNEL_ID) != null) return

        val channel = NotificationChannel(
            MARKETING_CHANNEL_ID,
            "عروض وخصومات",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "عروض المطاعم والمطابخ. مالهاش علاقة بحالة الأوردر."
        }

        manager.createNotificationChannel(channel)
    }

    companion object {
        /**
         * Also named in AndroidManifest.xml as the FCM default channel, so a message
         * arriving with the app closed lands here rather than on a channel Android
         * invents with default importance and no sound.
         *
         * Matches `LuqmaPush.quietChannel` and the `channel` the order-status trigger
         * writes into `push_outbox`. Three places, one string: if they drift, the
         * notification arrives on a channel nobody configured.
         */
        const val ORDERS_CHANNEL_ID = "orders"

        /**
         * Matches the `marketing` value `push_outbox.channel` has allowed since the day
         * that table existed, with a comment saying operational alerts must not be
         * silenced by the switch somebody flipped for marketing. This channel is what
         * makes that true on the phone rather than only in the schema.
         */
        const val MARKETING_CHANNEL_ID = "marketing"
    }
}
