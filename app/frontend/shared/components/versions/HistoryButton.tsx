import { router } from '@inertiajs/react';
import { ActionIcon, Tooltip } from '@mantine/core';
import { IconHistory } from '@tabler/icons-react';
import { useState } from 'react';

import type { VersionableType } from 'shared/lib/versionSchemas';

import { VersionHistoryDrawer } from './VersionHistoryDrawer';

interface HistoryButtonProps {
  projectId: number;
  versionableType: VersionableType;
  versionableId: number;
  title: string;
  canRevert: boolean;
  size?: 'sm' | 'md';
}

/** A row's History action: opens the entity's version timeline; a revert reloads the page. */
export function HistoryButton({
  projectId,
  versionableType,
  versionableId,
  title,
  canRevert,
  size = 'sm',
}: HistoryButtonProps) {
  const [opened, setOpened] = useState(false);

  return (
    <>
      <Tooltip label="History">
        <ActionIcon aria-label={`History of ${title}`} variant="subtle" size={size} onClick={() => setOpened(true)}>
          <IconHistory size={16} />
        </ActionIcon>
      </Tooltip>
      {opened && (
        <VersionHistoryDrawer
          opened
          onClose={() => setOpened(false)}
          projectId={projectId}
          versionableType={versionableType}
          versionableId={versionableId}
          title={title}
          canRevert={canRevert}
          onReverted={() => router.reload()}
        />
      )}
    </>
  );
}
