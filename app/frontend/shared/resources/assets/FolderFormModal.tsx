import { Button, Group, Modal, Stack, Text, TextInput } from '@mantine/core';
import { IconCheck } from '@tabler/icons-react';
import { useEffect, useRef, useState } from 'react';

export interface FolderFormModalProps {
  opened: boolean;
  onClose: () => void;
  mode: 'create' | 'rename';
  /** create: label of the folder being created into ('Assets (root)' at the top level). */
  parentLabel?: string;
  /** rename: the folder's current label, prefilled and selected. */
  initialName?: string;
  /** Names already taken at this location — folders and files alike, for an inline collision error. */
  existingNames: string[];
  submitting: boolean;
  /** Server-side error surfaced after a submit attempt (e.g. a race the client check missed). */
  serverError?: string | null;
  onSubmit: (name: string) => void;
}

const NAME_FORMAT = /^[a-zA-Z0-9_-]+$/;

export function FolderFormModal({
  opened,
  onClose,
  mode,
  parentLabel,
  initialName,
  existingNames,
  submitting,
  serverError,
  onSubmit,
}: FolderFormModalProps) {
  const [name, setName] = useState('');
  const [touched, setTouched] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (!opened) return;
    setName(mode === 'rename' ? (initialName ?? '') : '');
    setTouched(false);
    const id = setTimeout(() => {
      inputRef.current?.focus();
      if (mode === 'rename') inputRef.current?.select();
    }, 50);
    return () => clearTimeout(id);
  }, [opened, mode, initialName]);

  const trimmed = name.trim();
  const clientError = !touched
    ? null
    : !trimmed
      ? 'Folder name is required.'
      : trimmed.includes('/')
        ? 'Folder names can’t contain "/".'
        : !NAME_FORMAT.test(trimmed)
          ? 'Only letters, digits, hyphens and underscores are allowed.'
          : existingNames.includes(trimmed) && trimmed !== initialName
            ? `An item named "${trimmed}" already exists here.`
            : null;

  const errorText = clientError ?? serverError ?? null;

  const submit = () => {
    setTouched(true);
    if (!trimmed || trimmed.includes('/') || !NAME_FORMAT.test(trimmed)) return;
    if (existingNames.includes(trimmed) && trimmed !== initialName) return;
    onSubmit(trimmed);
  };

  return (
    <Modal
      opened={opened}
      onClose={onClose}
      title={mode === 'create' ? 'New folder' : 'Rename folder'}
      centered
      size="sm"
    >
      <Stack gap="md">
        <div>
          <Text size="sm" fw={600} mb={8}>
            Folder name{' '}
            <Text component="span" c="red" span>
              *
            </Text>
          </Text>
          <TextInput
            ref={inputRef}
            value={name}
            onChange={(e) => {
              setName(e.currentTarget.value);
              setTouched(true);
            }}
            onKeyDown={(e) => {
              if (e.key === 'Enter') submit();
            }}
            placeholder="e.g. specs"
            error={!!errorText}
            disabled={submitting}
          />
          {errorText && (
            <Text size="xs" c="red" mt={6}>
              {errorText}
            </Text>
          )}
          {!errorText && mode === 'create' && (
            <Text size="xs" c="dimmed" mt={6}>
              Creating inside: {parentLabel || 'Assets (root)'}
            </Text>
          )}
        </div>
      </Stack>
      <Group justify="flex-end" mt="lg">
        <Button variant="default" onClick={onClose} disabled={submitting}>
          Cancel
        </Button>
        <Button leftSection={<IconCheck size={16} />} onClick={submit} loading={submitting}>
          {mode === 'create' ? 'Create' : 'Save'}
        </Button>
      </Group>
    </Modal>
  );
}
