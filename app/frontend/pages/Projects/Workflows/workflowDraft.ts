import { router } from '@inertiajs/react';
import { useEffect, useState } from 'react';

import { apiRequest } from 'shared/lib/apiFetch';
import type { References, Snapshot } from 'shared/lib/versionDiff';
import {
  apiV1ProjectWorkflowDraftPath,
  applyApiV1ProjectWorkflowDraftPath,
  changesApiV1ProjectWorkflowDraftPath,
} from 'shared/routes';

import type { aggregatePayload } from './builderDraft';

/** On a live workflow's page: its open draft. */
export interface OpenDraft {
  id: number;
  updatedAt: string;
  updatedBy: string | null;
}

/** On a draft's page: the live workflow it is a draft of. */
export interface DraftOf {
  id: number;
  name: string;
  currentVersionNumber: number;
  baseVersionNumber: number;
}

export interface DraftChanges {
  live: Snapshot;
  draft: Snapshot;
  references: References;
  liveVersionNumber: number;
  baseVersionNumber: number;
  draftVersionNumber: number;
}

interface ApplyResult {
  currentVersionNumber: number;
  versionCreated: boolean;
  url: string;
}

const postJson = (body: unknown): RequestInit => ({
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(body),
});

/** Opens the live workflow's draft, or with `aggregate` makes a new one holding those edits. */
export const createDraft = (projectId: number, liveId: number, aggregate?: ReturnType<typeof aggregatePayload>) =>
  apiRequest<{ draftId: number; url: string }>(
    apiV1ProjectWorkflowDraftPath(projectId, liveId),
    postJson(aggregate ? { aggregate } : {}),
  );

export const fetchDraftChanges = (projectId: number, liveId: number) =>
  apiRequest<DraftChanges>(changesApiV1ProjectWorkflowDraftPath(projectId, liveId));

export const applyDraft = (projectId: number, liveId: number, overwrite: boolean) =>
  apiRequest<ApplyResult>(
    applyApiV1ProjectWorkflowDraftPath(projectId, liveId),
    postJson(overwrite ? { overwrite } : {}),
  );

export const discardDraft = (projectId: number, liveId: number) =>
  apiRequest<{ url: string }>(apiV1ProjectWorkflowDraftPath(projectId, liveId), { method: 'DELETE' });

/**
 * Leaves the page for `url` once the edits on it no longer count as unsaved: they went into the
 * draft, or the draft they belong to is closed. `leaving` is what the unsaved-changes guard reads.
 */
export function useLeaveTo() {
  const [target, setTarget] = useState<{ url: string } | null>(null);

  // The guard reads `leaving` from a render, so a visit in the same tick would still be asked about.
  useEffect(() => {
    if (target) router.visit(target.url);
  }, [target]);

  return { leaving: target !== null, leaveTo: (url: string) => setTarget({ url }) };
}
