import { Box, Button, Group, Modal, ScrollArea, Text, UnstyledButton } from '@mantine/core';
import { IconFolder, IconHome } from '@tabler/icons-react';
import { useState } from 'react';

export interface MoveToFolderModalProps {
  opened: boolean;
  onClose: () => void;
  /** What's being moved, e.g. "3 files" or a single file/folder's name — shown in the title. */
  subjectLabel: string;
  /** Every known folder path (persisted + derived), unsorted is fine — sorted here. */
  folderPaths: string[];
  /** Paths that can't be the destination — the item's own current folder, and (when moving a
   * folder) that folder's whole subtree, so it can't be dropped inside itself. */
  disabledPaths?: string[];
  submitting: boolean;
  onConfirm: (destinationPath: string) => void;
}

/** A folder-tree destination picker — root plus every folder, indented by depth. */
export function MoveToFolderModal({
  opened,
  onClose,
  subjectLabel,
  folderPaths,
  disabledPaths = [],
  submitting,
  onConfirm,
}: MoveToFolderModalProps) {
  const [destination, setDestination] = useState<string | null>(null);

  const sorted = [...new Set(folderPaths)].sort((a, b) => a.localeCompare(b));
  const disabled = new Set(disabledPaths);

  const submit = () => {
    if (destination === null) return;
    onConfirm(destination);
  };

  return (
    <Modal opened={opened} onClose={onClose} title={`Move ${subjectLabel}`} centered size="sm">
      <Text size="sm" c="dimmed" mb="sm">
        Choose a destination folder.
      </Text>
      <Box style={{ border: '1px solid var(--app-border-default)', borderRadius: 8, overflow: 'hidden' }}>
        <ScrollArea.Autosize mah={280} type="scroll">
          <DestinationOption
            path=""
            label="Assets (root)"
            icon={<IconHome size={14} />}
            depth={0}
            selected={destination === ''}
            disabled={disabled.has('')}
            onSelect={setDestination}
          />
          {sorted.map((path) => (
            <DestinationOption
              key={path}
              path={path}
              label={path}
              icon={<IconFolder size={14} />}
              depth={path.split('/').length - 1}
              selected={destination === path}
              disabled={disabled.has(path)}
              onSelect={setDestination}
            />
          ))}
        </ScrollArea.Autosize>
      </Box>
      <Group justify="flex-end" mt="lg">
        <Button variant="default" onClick={onClose} disabled={submitting}>
          Cancel
        </Button>
        <Button onClick={submit} loading={submitting} disabled={destination === null}>
          Move here
        </Button>
      </Group>
    </Modal>
  );
}

function DestinationOption({
  path,
  label,
  icon,
  depth,
  selected,
  disabled,
  onSelect,
}: {
  path: string;
  label: string;
  icon: React.ReactNode;
  depth: number;
  selected: boolean;
  disabled: boolean;
  onSelect: (path: string) => void;
}) {
  return (
    <UnstyledButton
      role="radio"
      aria-checked={selected}
      aria-disabled={disabled}
      onClick={() => !disabled && onSelect(path)}
      style={{
        display: 'flex',
        alignItems: 'center',
        gap: 8,
        width: '100%',
        padding: '8px 12px',
        paddingLeft: 12 + depth * 16,
        background: selected ? 'var(--app-action-selected)' : 'transparent',
        color: disabled ? 'var(--app-text-tertiary)' : 'var(--app-text-primary)',
        cursor: disabled ? 'not-allowed' : 'pointer',
        opacity: disabled ? 0.5 : 1,
      }}
    >
      {icon}
      <Text size="sm" truncate="end" style={{ flex: 1, minWidth: 0 }} title={label}>
        {label}
      </Text>
    </UnstyledButton>
  );
}
