/**
 * The FCM v1 message for one device, built from one `push_outbox` row.
 *
 * Plain TypeScript with no Deno import, so the suite runs it under Node
 * (`supabase/test/local/what_a_push_tells_the_phone.test.js`).
 */
export interface OutboxRow {
  title: string;
  body: string;
  channel: string;
  data?: Record<string, unknown> | null;
}

export function fcmMessage(row: OutboxRow, to: string) {
  return {
    token: to,
    // **Both** blocks, and this is the whole delivery story.
    //
    // It was `data` only, on the reasoning that a `notification` payload makes
    // Android draw the alert itself so the app never runs and the looping alarm
    // never plays. That reasoning is wrong, and it cost the feature: the alarm
    // does not come from the app drawing the notification, it comes from the
    // **channel** — `orders_critical` is created natively with the alarm sound,
    // MAX importance and DND bypass, so a system-drawn alert on that channel
    // sounds exactly like an app-drawn one.
    //
    // What data-only actually bought was silence. A data-only message displays
    // nothing by itself; it needs the background isolate to wake and render, and
    // that isolate does not run when the app has been swiped away, on a phone in
    // battery saver, or on most of the OEM builds sold in Egypt. So the merchant
    // got their alarm only while the app was open — which is the one case that
    // needed no notification at all.
    notification: { title: row.title, body: row.body },
    data: {
      title: row.title,
      body: row.body,
      channel: row.channel,
      ...Object.fromEntries(
        Object.entries(row.data ?? {}).map(([k, v]) => [k, String(v)]),
      ),
    },
    android: {
      priority: 'HIGH',
      // Woken even in Doze. This is the notification the shop's evening depends
      // on, and a phone on a shelf is a phone Android has put to sleep.
      ttl: '3600s',
      notification: {
        // Which channel decides the sound, the importance and whether it gets
        // through Do Not Disturb. Named per message rather than fixed, because
        // the customer's "your food is on the way" must not arrive with the
        // kitchen's alarm.
        channel_id: row.channel,
        notification_priority: 'PRIORITY_MAX',
        // No `click_action`. It named FLUTTER_NOTIFICATION_CLICK, which no manifest
        // declares an activity for, so tapping a notification Android drew itself — the
        // app closed or in the background — opened nothing in any of the three apps
        // (reported by the owner, 2026-09-24). Left out, the tap opens the launcher
        // activity and firebase_messaging hands the app the message, whose `data` says
        // which order it was about.
      },
    },
  };
}
