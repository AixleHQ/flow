import { router } from '@inertiajs/react';
import { Button, Group, Modal, Select, Stack, Text } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useCallback, useEffect, useState } from 'react';

import type { Integration } from '@/types/generated';

interface Props {
  integration: Integration | null;
  onClose: () => void;
  onCreated: (integration: Integration) => void;
  basePath: string;
}

// Finishes a GitLab sign-in: Flow creates its service account in the group picked here.
export const GitlabGroupModal = ({ integration, onClose, onCreated, basePath }: Props) => {
  const groups = integration?.gitlabGroups ?? [];
  const [groupId, setGroupId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    const owned = integration?.gitlabGroups ?? [];
    setGroupId(owned.length === 1 ? owned[0].id : null);
  }, [integration]);

  const save = useCallback(() => {
    if (!integration || !groupId) return;
    setSaving(true);
    router.patch(
      `${basePath}/${integration.id}`,
      { gitlabGroupId: groupId },
      {
        preserveScroll: true,
        onSuccess: () => onCreated(integration),
        onError: () => notifications.show({ message: 'Failed to create the service account', color: 'red' }),
        onFinish: () => setSaving(false),
      },
    );
  }, [basePath, groupId, integration, onCreated]);

  return (
    <Modal opened={!!integration} onClose={onClose} title="Pick the GitLab group" size="md">
      <Stack gap="md">
        <Text size="sm" c="dimmed">
          Flow creates a service account in this group, or reuses the one it made there before, makes it a Maintainer
          and keeps only its token: repositories, merge requests and issues are then reached as that account, not as
          you. It sees the group&apos;s projects; invite it to others in GitLab.
        </Text>
        <Select
          label="Group"
          placeholder="Pick a group you own"
          data={groups.map((g) => ({ value: g.id, label: g.fullPath }))}
          value={groupId}
          onChange={setGroupId}
          searchable
        />
        <Group justify="flex-end">
          <Button variant="default" onClick={onClose}>
            Cancel
          </Button>
          <Button onClick={save} loading={saving} disabled={!groupId}>
            Create service account
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
};
