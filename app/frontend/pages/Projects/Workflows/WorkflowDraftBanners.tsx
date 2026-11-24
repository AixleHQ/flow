import { Link } from '@inertiajs/react';
import { Alert, Anchor, Button, Group, Text } from '@mantine/core';
import { IconAlertTriangle, IconGitBranch } from '@tabler/icons-react';

import { formatDateTimeShort } from 'shared/lib/formatDate';
import { builderCompanyProjectWorkflowPath, draftCompanyProjectWorkflowPath } from 'shared/routes';

import type { DraftOf, OpenDraft } from './workflowDraft';

const BANNER_STYLE = { flexShrink: 0, borderBottom: '1px solid var(--app-border-default)' };

/** On the live workflow's page: it has an open draft. */
export function OpenDraftBanner({
  projectId,
  workflowId,
  draft,
}: {
  projectId: number;
  workflowId: number;
  draft: OpenDraft;
}) {
  const by = draft.updatedBy ? ` by ${draft.updatedBy}` : '';
  return (
    <Alert icon={<IconGitBranch size={16} />} color="blue" radius={0} style={BANNER_STYLE}>
      <Group justify="space-between" wrap="nowrap" gap="md">
        <Text fz="sm">
          {`This workflow has an open draft, last changed ${formatDateTimeShort(draft.updatedAt)}${by}. ` +
            'Triggers keep running this live version until the draft is applied.'}
        </Text>
        <Button
          component={Link}
          href={draftCompanyProjectWorkflowPath(projectId, workflowId)}
          size="compact-sm"
          variant="light"
          style={{ flexShrink: 0 }}
        >
          Open draft
        </Button>
      </Group>
    </Alert>
  );
}

/** On a draft's page: what runs where, and whether the live workflow moved on since the draft was made. */
export function DraftOfBanner({ projectId, draftOf }: { projectId: number; draftOf: DraftOf }) {
  const { name, currentVersionNumber: current, baseVersionNumber: base } = draftOf;
  return (
    <Alert icon={<IconAlertTriangle size={16} />} color="yellow" radius={0} style={BANNER_STYLE}>
      <Text fz="sm">
        {`Draft of “${name}”. Triggers and board columns keep running the live workflow (v${current}); ` +
          'runs started here run this draft. '}
        <Anchor component={Link} href={builderCompanyProjectWorkflowPath(projectId, draftOf.id)} fz="sm">
          Open live workflow
        </Anchor>
      </Text>
      {current !== base && (
        <Text fz="sm" mt={4}>
          {`The live workflow changed after this draft was made (v${base} → v${current}). ` +
            'Applying the draft replaces those changes too.'}
        </Text>
      )}
    </Alert>
  );
}
