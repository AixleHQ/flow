/**
 * What to tell a person whose session is not up yet.
 *
 * A session stays in `queued` from the moment its row is written until the
 * container workflow's first activity starts it — right through dispatch — so
 * that state covers both "nobody has a slot for you" and "your slot is granted,
 * the container is coming up". Two screens read it as the first meaning and
 * said so: an authentication session that was granted its slot in one second
 * spent its whole launch telling the user to wait for capacity, with the user's
 * own limit nowhere near full. A launch that failed outright said the same
 * thing, forever.
 *
 * `launchPhase` (SessionAdmission#launch_phase) is the fact that separates them,
 * and this module is the single place that turns it into words.
 */

export type LaunchPhase = 'queued_for_slot' | 'starting' | 'cluster_capacity' | 'namespace_quota' | 'running';

/** True only when the session really is behind other sessions in its pool. */
export function isWaitingForSlot(phase: string | null | undefined): boolean {
  return phase === 'queued_for_slot';
}

/** True when the cluster, not the pool, is what has no room. */
export function isWaitingForCluster(phase: string | null | undefined): boolean {
  return phase === 'cluster_capacity' || phase === 'namespace_quota';
}

/**
 * The headline for a session that is not up yet. `kind` only changes the noun:
 * an authentication session is not "a session" to the person who started it.
 */
export function launchWaitMessage(
  phase: string | null | undefined,
  kind: 'session' | 'authentication' = 'session',
): string {
  if (isWaitingForSlot(phase)) return 'Waiting for a free session slot';
  if (isWaitingForCluster(phase)) return 'Waiting for cluster capacity';

  return kind === 'authentication' ? 'Starting authentication session…' : 'Starting session…';
}
