import { router } from '@inertiajs/react';
import { Alert, Button, Stack, TextInput } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useEffect, useState } from 'react';

import type { ProjectTracker } from '@/types/generated';

import { useConfirmClose } from 'shared/lib/hooks/useConfirmClose';
import { ResourceDrawer } from 'shared/ui/ResourceDrawer';

import { HANDLE_FORMAT } from './AddTrackerDrawer';

interface Props {
  tracker: ProjectTracker | null;
  basePath: string;
  onClose: () => void;
}

export const EditHandleDrawer = ({ tracker, basePath, onClose }: Props) => {
  const [handle, setHandle] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!tracker) return;
    setHandle(tracker.handle);
    setError(null);
  }, [tracker]);

  const value = handle.trim().toLowerCase();
  const invalid = value !== '' && !HANDLE_FORMAT.test(value);
  const ready = Boolean(tracker && value && !invalid && value !== tracker.handle);
  const requestClose = useConfirmClose(tracker !== null && handle !== tracker.handle, onClose);

  const submit = () => {
    if (!tracker || !ready) return;
    setSaving(true);
    setError(null);
    router.patch(
      `${basePath}/${tracker.id}`,
      { tracker: { handle: value } },
      {
        preserveScroll: true,
        onSuccess: () => {
          notifications.show({ message: 'Handle changed', color: 'green' });
          onClose();
        },
        onError: (errors) => setError(Object.values(errors)[0] ?? 'Failed to change the handle'),
        onFinish: () => setSaving(false),
      },
    );
  };

  return (
    <ResourceDrawer
      opened={Boolean(tracker)}
      onClose={requestClose}
      title="Edit handle"
      footer={
        <Button fullWidth loading={saving} disabled={!ready} onClick={submit}>
          Save handle
        </Button>
      }
    >
      <Stack gap="md">
        {error && <Alert color="red">{error}</Alert>}
        <TextInput
          label="Handle"
          description="What agents call this tracker: they pass it as `tracker`. Instructions that name the old handle stop finding it; triggers are not affected."
          value={handle}
          onChange={(e) => setHandle(e.currentTarget.value)}
          error={invalid ? 'Lowercase letters, digits and dashes' : undefined}
          withAsterisk
        />
      </Stack>
    </ResourceDrawer>
  );
};
