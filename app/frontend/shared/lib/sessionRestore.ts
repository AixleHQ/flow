import { router } from '@inertiajs/react';

import { apiRequest, notifyApiFailure } from 'shared/lib/apiFetch';
import { companyProjectSessionPath, companySessionPath, restoreApiV1TerminalSessionPath } from 'shared/routes';

export interface RestoredSession {
  id: number;
  projectId: number | null;
}

function sessionPage(session: RestoredSession): string {
  return session.projectId ? companyProjectSessionPath(session.projectId, session.id) : companySessionPath(session.id);
}

/**
 * Starts the session that continues a suspended one and opens it — on the session
 * page, or where `hrefFor` says (Aixle Builder has its own). Resolves false (after a
 * toast with the server's reason) when the restore was refused.
 */
export async function restoreSession(
  sessionId: number,
  hrefFor: (session: RestoredSession) => string = sessionPage,
): Promise<boolean> {
  try {
    const restored = await apiRequest<RestoredSession>(restoreApiV1TerminalSessionPath(sessionId), { method: 'POST' });
    router.visit(hrefFor(restored));
    return true;
  } catch (error) {
    notifyApiFailure(error, 'The session could not be restored');
    return false;
  }
}

/** Whole days left before a suspended session can no longer be restored. */
export function restoreDaysLeft(expiresAt: string | null, now: number = Date.now()): number | null {
  if (!expiresAt) return null;
  return Math.max(0, Math.ceil((new Date(expiresAt).getTime() - now) / 86_400_000));
}
