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
    }
}
