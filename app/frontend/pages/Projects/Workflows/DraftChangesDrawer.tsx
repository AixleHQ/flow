import { Alert, Drawer, Loader, Stack, Text } from '@mantine/core';
import { useEffect, useMemo, useState } from 'react';

import { VersionDiff } from 'shared/components/versions/VersionDiff';
import { notifyApiFailure } from 'shared/lib/apiFetch';
import { diffSnapshots } from 'shared/lib/versionDiff';
import { VERSION_SCHEMAS } from 'shared/lib/versionSchemas';

import { type DraftChanges, type DraftOf, fetchDraftChanges } from './workflowDraft';

interface Props {
  onClose: () => void;
  projectId: number;
  draftOf: DraftOf;
  /** The editor holds edits the saved draft, and so this comparison, does not have. */
  dirty: boolean;
}

/** What applying the saved draft would change on the live workflow. Fetches once per mount. */
export function DraftChangesDrawer({ onClose, projectId, draftOf, dirty }: Props) {
  const [result, setResult] = useState<DraftChanges | 'failed' | null>(null);

  useEffect(() => {
    let current = true;
    fetchDraftChanges(projectId, draftOf.id).then(
      (changes) => current && setResult(changes),
      (error: unknown) => {
        if (!current) return;
        notifyApiFailure(error, 'Could not load what the draft changes');
        setResult('failed');
      },
    );
    return () => {
      current = false;
    };
  }, [projectId, draftOf.id]);

  const changes = useMemo(
    () =>
      result && result !== 'failed'
        ? diffSnapshots(VERSION_SCHEMAS.Workflow, result.live, result.draft, result.references)
        : [],
    [result],
  );

  return (
    <Drawer opened onClose={onClose} position="right" size={720} title={<Text fw={600}>What will change</Text>}>
      <Stack gap="sm">
        {dirty && (
          <Alert color="yellow" variant="light">
            Your unsaved edits are not included. Save the draft to see them here.
          </Alert>
        )}
        {result === null ? (
          <Loader size="sm" />
        ) : result === 'failed' ? (
          <Text fz={14} c="dimmed">
            Could not load the changes.
          </Text>
        ) : changes.length === 0 ? (
          <Text fz={14} c="dimmed">
            No changes yet
          </Text>
        ) : (
          <>
            <Text fz={13} c="dimmed">
              {`Applying the draft makes these changes to “${draftOf.name}” (live v${result.liveVersionNumber}):`}
            </Text>
            <VersionDiff changes={changes} />
          </>
        )}
      </Stack>
    </Drawer>
  );
}
