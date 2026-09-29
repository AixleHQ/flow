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
      title="Archive Skill"
      confirmLabel="Archive"
      itemId={skill.id}
      basePath={basePath}
      description={
        <>
          Archive skill{' '}
          <Text span fw={600} c="var(--app-text-primary)">
            {skill.title || skill.name}
          </Text>
          ? It disappears from pickers and new sessions but keeps its history, and you can restore it from the Archived
          tab. Archiving is refused while a workflow uses it.
        </>
      }
      onDeleteError={() => notifications.show({ message: 'Failed to archive skill', color: 'red' })}
    />
  );
};
