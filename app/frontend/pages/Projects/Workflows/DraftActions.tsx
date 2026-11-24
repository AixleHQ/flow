import { Alert, Button, Group, Modal, Stack, Text, Tooltip } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconCheck, IconListDetails, IconTrash } from '@tabler/icons-react';
import { useState } from 'react';

import { ApiError, notifyApiFailure } from 'shared/lib/apiFetch';

import { DraftChangesDrawer } from './DraftChangesDrawer';
import { applyDraft, discardDraft, type DraftOf } from './workflowDraft';

interface Props {
  projectId: number;
  draftOf: DraftOf;
  dirty: boolean;
  /** Leaves the draft's page once it is applied or discarded. */
  onLeave: (url: string) => void;
}

/** The draft page's own header actions: see what it changes, apply it, discard it. */
export function DraftActions({ projectId, draftOf, dirty, onLeave }: Props) {
  const [changesOpen, setChangesOpen] = useState(false);
  const [applyOpen, setApplyOpen] = useState(false);
  const [discardOpen, setDiscardOpen] = useState(false);
  const [conflict, setConflict] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const apply = async (overwrite: boolean) => {
    setBusy(true);
    try {
      const result = await applyDraft(projectId, draftOf.id, overwrite);
      notifications.show({
        color: 'green',
        message: result.versionCreated
          ? `Draft applied as version ${result.currentVersionNumber}`
          : 'Draft closed — it changed nothing',
      });
      onLeave(result.url);
    } catch (error) {
      if (error instanceof ApiError && error.status === 409) setConflict(error.message);
      else notifyApiFailure(error, 'The draft was not applied');
      setBusy(false);
    }
  };

  const discard = async () => {
    setBusy(true);
    try {
      const { url } = await discardDraft(projectId, draftOf.id);
      onLeave(url);
    } catch (error) {
      notifyApiFailure(error, 'The draft was not discarded');
      setBusy(false);
    }
  };

  const closeApply = () => {
    setApplyOpen(false);
    setConflict(null);
  };

  return (
    <>
      <Button
        size="compact-sm"
        variant="default"
        leftSection={<IconListDetails size={14} />}
        onClick={() => setChangesOpen(true)}
      >
        What will change
      </Button>
      <Button
        size="compact-sm"
        variant="subtle"
        color="red"
        leftSection={<IconTrash size={14} />}
        onClick={() => setDiscardOpen(true)}
      >
        Discard draft
      </Button>
      <Tooltip label="Save the draft first" disabled={!dirty}>
        {/* data-disabled, not disabled: a disabled button gets no hover, so the tooltip could not say why. */}
        <Button
          size="compact-sm"
          leftSection={<IconCheck size={14} />}
          data-disabled={dirty || undefined}
          aria-disabled={dirty || undefined}
          onClick={() => !dirty && setApplyOpen(true)}
        >
          Apply
        </Button>
      </Tooltip>

      {changesOpen && (
        <DraftChangesDrawer
          onClose={() => setChangesOpen(false)}
          projectId={projectId}
          draftOf={draftOf}
          dirty={dirty}
        />
      )}

      <Modal opened={applyOpen} onClose={closeApply} title={`Apply this draft to “${draftOf.name}”?`} centered>
        <Stack gap="md">
          <Text fz="sm">It becomes the live version, and triggers run it from then on.</Text>
          {conflict && (
            <Alert color="yellow" variant="light">
              {conflict}
            </Alert>
          )}
          <Group justify="flex-end">
            <Button variant="default" onClick={closeApply} disabled={busy}>
              Cancel
            </Button>
            <Button onClick={() => void apply(conflict !== null)} loading={busy}>
              {conflict ? 'Apply anyway' : 'Apply'}
            </Button>
          </Group>
        </Stack>
      </Modal>

      <Modal opened={discardOpen} onClose={() => setDiscardOpen(false)} title="Discard this draft?" centered>
        <Stack gap="md">
          <Text fz="sm">The live workflow stays as it is.</Text>
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setDiscardOpen(false)} disabled={busy}>
              Cancel
            </Button>
            <Button color="red" onClick={() => void discard()} loading={busy}>
              Discard
            </Button>
          </Group>
        </Stack>
      </Modal>
    </>
  );
}
