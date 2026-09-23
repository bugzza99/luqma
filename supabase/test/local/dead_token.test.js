import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { isDeadToken } from '../../functions/send-push/dead_token.ts';

/**
 * A14. Which FCM answers prune a device token.
 *
 * `send-push` pruned on INVALID_ARGUMENT outright, and FCM uses that code for a malformed
 * *message* as well as for a token that is not one — so a single bad row took every
 * recipient's phone off the list. Only an answer that is about the token prunes it.
 */
describe('which answers mean a token is dead', () => {
  const fcm = (status, errorCode, message = '') =>
    ({ error: { status, message, details: errorCode ? [{ errorCode }] : [] } });

  it('a token the app no longer holds', () =>
    assert.equal(isDeadToken(fcm('NOT_FOUND', 'UNREGISTERED')), true));

  it('a token from another project', () =>
    assert.equal(isDeadToken(fcm('PERMISSION_DENIED', 'SENDER_ID_MISMATCH')), true));

  it('a token that is not a token', () => assert.equal(isDeadToken(fcm(
    'INVALID_ARGUMENT', 'INVALID_ARGUMENT',
    'The registration token is not a valid FCM registration token')), true));

  it('a message FCM cannot accept is not the device', () => assert.equal(isDeadToken(fcm(
    'INVALID_ARGUMENT', 'INVALID_ARGUMENT',
    'Invalid value at \'message.android.notification.channel_id\'')), false));

  it('a busy server is not a dead device', () => {
    assert.equal(isDeadToken(fcm('UNAVAILABLE', 'UNAVAILABLE')), false);
    assert.equal(isDeadToken(fcm('RESOURCE_EXHAUSTED', 'QUOTA_EXCEEDED')), false);
    assert.equal(isDeadToken(fcm('INTERNAL', 'INTERNAL')), false);
  });

  it('nothing to read is nothing to prune', () => {
    assert.equal(isDeadToken({}), false);
    assert.equal(isDeadToken(null), false);
  });
});
