/**
 * Whether FCM's answer means this token will never work again, so it can be pruned.
 *
 * A14. `INVALID_ARGUMENT` was on the list outright, and FCM uses it for two different
 * things: a token that is not a token, and a *message* it cannot accept — a field too
 * long, a value of the wrong type. The second is the sender's fault and says nothing
 * about the device, yet it pruned the token of every recipient the bad message was sent
 * to: one malformed row, and a whole shop's phones stop ringing until somebody opens the
 * app again. It counts as dead only when FCM names the registration token as the
 * problem.
 *
 * Plain TypeScript with no Deno import, so the suite runs it under Node.
 */
export function isDeadToken(body: unknown): boolean {
  const error = (body as { error?: Record<string, unknown> } | null)?.error;
  if (!error || typeof error !== 'object') return false;

  const details = Array.isArray(error.details) ? error.details : [];
  const code = String(
    (details[0] as { errorCode?: unknown } | undefined)?.errorCode ?? error.status ?? '',
  );

  if (code === 'UNREGISTERED' || code === 'SENDER_ID_MISMATCH') return true;
  if (code === 'INVALID_ARGUMENT') {
    return /registration token/i.test(String(error.message ?? ''));
  }
  return false;
}
