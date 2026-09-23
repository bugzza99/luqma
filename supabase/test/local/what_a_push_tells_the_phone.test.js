import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { fcmMessage } from '../../functions/send-push/message.ts';

/**
 * What `send-push` hands FCM for one device.
 *
 * The owner reported, 2026-09-24, that tapping a notification did nothing in any of the
 * three apps. Every message carried `click_action: FLUTTER_NOTIFICATION_CLICK`, and no
 * manifest declares an activity for that action — so a notification Android drew itself
 * (the app closed or in the background) opened nothing when tapped. Without it, Android
 * opens the app's launcher activity, and firebase_messaging hands the app the message
 * (`getInitialMessage` / `onMessageOpenedApp`), which already knows where to go.
 */
describe('what a push tells the phone', () => {
  const row = {
    title: 'أوردر جديد',
    body: 'طلب من أحمد',
    channel: 'orders_critical',
    data: { kind: 'newOrder', orderId: 'o1', number: 7 },
  };

  it('names no click action, so a tap opens the app', () => {
    const m = fcmMessage(row, 'tok-1');
    assert.equal(m.android.notification.click_action, undefined);
    assert.doesNotMatch(JSON.stringify(m), /click_action/);
  });

  it('is addressed to the one device', () => {
    assert.equal(fcmMessage(row, 'tok-1').token, 'tok-1');
  });

  it('draws on the channel the row names, woken through Doze', () => {
    const m = fcmMessage(row, 'tok-1');
    assert.equal(m.android.priority, 'HIGH');
    assert.equal(m.android.notification.channel_id, 'orders_critical');
    assert.deepEqual(m.notification, { title: 'أوردر جديد', body: 'طلب من أحمد' });
  });

  it('carries the payload as strings, which is all FCM data allows', () => {
    const m = fcmMessage(row, 'tok-1');
    assert.equal(m.data.orderId, 'o1');
    assert.equal(m.data.number, '7');
    assert.equal(m.data.channel, 'orders_critical');
  });
});
