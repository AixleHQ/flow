import { router } from '@inertiajs/react';
import { Button, Group, Modal, Select, Stack, Text } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useCallback, useEffect, useState } from 'react';

import type { Integration } from '@/types/generated';

interface Props {
  integration: Integration | null;
  onClose: () => void;
  basePath: string;
}

// Finishes a GitLab sign-in: Flow creates its service account in the group picked here.
export const GitlabGroupModal = ({ integration, onClose, basePath }: Props) => {
  const groups = integration?.gitlabGroups ?? [];
  const [groupId, setGroupId] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    setGroupId(groups.length === 1 ? groups[0].id : null);
  }, [groups]);

  const save = useCallback(() => {
    if (!integration || !groupId) return;
    setSaving(true);
    router.patch(
      `${basePath}/${integration.id}`,
      { gitlabGroupId: groupId },
      {
        preserveScroll: true,
        onSuccess: onClose,
        onError: () => notifications.show({ message: 'Failed to create the service account', color: 'red' }),
        onFinish: () => setSaving(false),
      },
    );
  }, [basePath, groupId, integration, onClose]);

  return (
    <Modal opened={!!integration} onClose={onClose} title="Pick the GitLab group" size="md">
      <Stack gap="md">
        <Text size="sm" c="dimmed">
          Flow creates a service account named Aixle Flow in this group, makes it a Maintainer and keeps only its token:
          repositories, merge requests and issues are then reached as that account, not as you. It sees the group&apos;s
          projects; invite it to others in GitLab.
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
