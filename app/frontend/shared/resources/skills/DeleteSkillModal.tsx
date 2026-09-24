import { Text } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { type FC } from 'react';

import type { Skill } from '@/types/generated';

import { ConfirmDeleteModal } from 'shared/ui/ConfirmDeleteModal';

interface DeleteSkillModalProps {
  opened: boolean;
  onClose: () => void;
  skill: Pick<Skill, 'id' | 'name' | 'title'> | null;
  basePath: string;
}

export const DeleteSkillModal: FC<DeleteSkillModalProps> = ({ opened, onClose, skill, basePath }) => {
  if (!skill) return null;

  return (
    <ConfirmDeleteModal
      opened={opened}
      onClose={onClose}
      title="Delete Skill"
      itemId={skill.id}
      basePath={basePath}
      description={
        <>
          Are you sure you want to delete skill{' '}
          <Text span fw={600} c="var(--app-text-primary)">
            {skill.title || skill.name}
          </Text>
          ? This action cannot be undone.
        </>
      }
      onDeleteError={() => notifications.show({ message: 'Failed to delete skill', color: 'red' })}
    />
  );
};
