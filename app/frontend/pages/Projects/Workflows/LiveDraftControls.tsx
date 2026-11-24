import { Button, Group, Modal, Stack, Text, Tooltip } from '@mantine/core';
import { IconGitBranch } from '@tabler/icons-react';
import { useState } from 'react';

import { notifyApiFailure } from 'shared/lib/apiFetch';

import type { aggregatePayload } from './builderDraft';
import { createDraft } from './workflowDraft';

/** Opens the live workflow's draft. Edits on the live page would not go with it, so it waits for a clean editor. */
export function EditInDraftButton({
  projectId,
  workflowId,
  dirty,
  onLeave,
}: {
  projectId: number;
  workflowId: number;
  dirty: boolean;
  onLeave: (url: string) => void;
}) {
  const [opening, setOpening] = useState(false);

  const open = async () => {
    setOpening(true);
    try {
      const { url } = await createDraft(projectId, workflowId);
      onLeave(url);
    } catch (error) {
      notifyApiFailure(error, 'The draft was not opened');
      setOpening(false);
    }
  };

  return (
    <Tooltip label="Save or discard your changes first" disabled={!dirty}>
      {/* data-disabled, not disabled: a disabled button gets no hover, so the tooltip could not say why. */}
      <Button
        size="compact-sm"
        variant="default"
        leftSection={<IconGitBranch size={14} />}
        loading={opening}
        data-disabled={dirty || undefined}
        aria-disabled={dirty || undefined}
        onClick={() => !dirty && void open()}
      >
        Edit in draft
      </Button>
    </Tooltip>
  );
}

interface SaveToLiveModalProps {
  opened: boolean;
  onClose: () => void;
  projectId: number;
  workflowId: number;
  triggerCount: number;
  hasDraft: boolean;
  /** The editor's unsaved state, as Save sends it. */
  aggregate: () => ReturnType<typeof aggregatePayload>;
  onSaveToLive: () => void;
  /** Leaves for the new draft, which now holds the edits. */
  onLeave: (url: string) => void;
}

/** Asked before a Save that changes what triggers and bound board columns run. */
export function SaveToLiveModal({
  opened,
  onClose,
  projectId,
  workflowId,
  triggerCount,
  hasDraft,
  aggregate,
  onSaveToLive,
  onLeave,
}: SaveToLiveModalProps) {
  const [savingDraft, setSavingDraft] = useState(false);

  const saveAsDraft = async () => {
    setSavingDraft(true);
    try {
      const { url } = await createDraft(projectId, workflowId, aggregate());
      onLeave(url);
    } catch (error) {
      notifyApiFailure(error, 'The draft was not created');
      setSavingDraft(false);
    }
  };

  const starters = triggerCount === 1 ? 'trigger or board column starts' : 'triggers or board columns start';

  return (
    <Modal opened={opened} onClose={onClose} title="Save to the live workflow?" centered>
      <Stack gap="md">
        <Text fz="sm">{`${triggerCount} ${starters} this workflow. Saving changes what they run from now on.`}</Text>
        {hasDraft && (
          <Text fz="sm" c="dimmed">
            This workflow has an open draft. Applying it later will ask before replacing this change.
          </Text>
        )}
        <Group justify="flex-end">
          <Button variant="default" onClick={onClose} disabled={savingDraft}>
            Cancel
          </Button>
          {!hasDraft && (
            <Button variant="light" onClick={() => void saveAsDraft()} loading={savingDraft}>
              Save as draft
            </Button>
          )}
          <Button onClick={onSaveToLive} disabled={savingDraft}>
            Save to live
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}
