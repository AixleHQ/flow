import { router } from '@inertiajs/react';
import { Box, Button, Group, Modal, Text } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useState, type FC } from 'react';

interface Skill {
  id: number;
  name: string;
  title: string | null;
}

interface DeleteSkillModalProps {
  opened: boolean;
  onClose: () => void;
  skill: Skill | null;
  basePath: string;
}

export const DeleteSkillModal: FC<DeleteSkillModalProps> = ({ opened, onClose, skill, basePath }) => {
  const [loading, setLoading] = useState(false);

  if (!skill) return null;

  const handleDelete = () => {
    setLoading(true);
    router.delete(`${basePath}/${skill.id}`, {
      preserveScroll: true,
      onSuccess: () => onClose(),
      onError: () => {
        notifications.show({ message: 'Failed to delete skill', color: 'red' });
      },
      onFinish: () => setLoading(false),
    });
  };

  return (
    <Modal opened={opened} onClose={onClose} title="Delete Skill" size="sm">
      <Box>
        <Text fz={14} c="dimmed" mb="md">
          Are you sure you want to delete skill{' '}
          <Text span fw={600} c="white">
            {skill.title || skill.name}
          </Text>
          ? This action cannot be undone.
        </Text>

        <Group justify="flex-end">
          <Button variant="default" onClick={onClose} disabled={loading}>
            Cancel
          </Button>
          <Button color="red" onClick={handleDelete} loading={loading}>
            Delete
          </Button>
        </Group>
      </Box>
    </Modal>
  );
};
