import { Button, Group, Text } from '@mantine/core';
import { modals } from '@mantine/modals';
import { useState } from 'react';

interface Answers {
  onDiscard: () => void;
  /** Resolves true once saved, and the leave goes ahead; false keeps the user on the form. */
  onSave?: () => Promise<boolean>;
}

function UnsavedChangesDialog({ onDiscard, onSave, onKeepEditing }: Answers & { onKeepEditing: () => void }) {
  const [saving, setSaving] = useState(false);

  const save = async () => {
    if (!onSave) return;
    setSaving(true);
    try {
      await onSave();
    } finally {
      setSaving(false);
    }
  };

  return (
    <>
      <Text size="sm">
        {onSave ? 'Your changes are not saved yet.' : 'What you entered in this form will be lost.'}
      </Text>
      <Group justify="flex-end" mt="md">
        <Button variant="default" onClick={onKeepEditing} disabled={saving}>
          Keep editing
        </Button>
        <Button color="red" variant={onSave ? 'light' : 'filled'} onClick={onDiscard} disabled={saving}>
          Discard
        </Button>
        {onSave && (
          <Button onClick={save} loading={saving}>
            Save
          </Button>
        )}
      </Group>
    </>
  );
}

let asking: string | null = null;

/** The one "unsaved changes" question in the app. A second ask while it is open is dropped. */
export function askUnsavedChanges({ onDiscard, onSave }: Answers) {
  if (asking) return;
  const id = `unsaved-changes-${Date.now()}`;
  asking = id;
  const close = () => modals.close(id);

  modals.open({
    modalId: id,
    title: onSave ? 'Save your changes?' : 'Discard unsaved changes?',
    children: (
      <UnsavedChangesDialog
        onKeepEditing={close}
        onDiscard={() => {
          close();
          onDiscard();
        }}
        onSave={
          onSave &&
          (async () => {
            // A failed save closes the question too: the form underneath shows why, and stays.
            const saved = await onSave().catch(() => false);
            close();
            return saved;
          })
        }
      />
    ),
    // Mantine listens for Escape on window, once per open modal, so the Escape that dismisses
    // this question also reaches the dialog underneath and calls back in here. Released only
    // after that event has finished, or it would re-open the question it just answered.
    onClose: () => {
      setTimeout(() => {
        if (asking === id) asking = null;
      });
    },
  });
}

/** Drops an open question once no form is left to answer it for. */
export function dismissUnsavedChangesQuestion() {
  if (asking) modals.close(asking);
  asking = null;
}
