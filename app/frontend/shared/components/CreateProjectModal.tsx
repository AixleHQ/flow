import { useForm } from '@inertiajs/react';
import { Alert, Button, Group, Modal, Stack, TextInput, Textarea } from '@mantine/core';

import { useUnsavedChanges } from 'shared/lib/unsaved-changes/useUnsavedChanges';

interface CreateProjectModalProps {
  opened: boolean;
  onClose: () => void;
}

const BLANK_PROJECT = { name: '', description: '' };

// Rails sends `model.errors.to_hash`: bare messages, often an array, keyed by attribute.
// Keys other than `name` have no field in this form, so they need the attribute to make sense.
const errorMessages = (errors: Record<string, string | string[] | undefined>) =>
  Object.entries(errors).flatMap(([key, value]) => {
    const messages = ([] as string[]).concat(value ?? []);
    if (key === 'base') return messages;
    const label = key.charAt(0).toUpperCase() + key.slice(1).replace(/_/g, ' ');
    return messages.map((message) => `${label} ${message}`);
  });

export const CreateProjectModal = ({ opened, onClose }: CreateProjectModalProps) => {
  const { data, setData, post, processing, errors, reset, clearErrors, transform } = useForm(BLANK_PROJECT);

  const handleClose = () => {
    reset();
    clearErrors();
    onClose();
  };
  const dirty = data.name !== BLANK_PROJECT.name || data.description !== BLANK_PROJECT.description;
  const requestClose = useUnsavedChanges({ opened, dirty, onClose: handleClose });
  const messages = errorMessages(errors);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    transform((d) => ({ project: d }));
    post('/company/projects', {
      onSuccess: handleClose,
    });
  };

  return (
    <Modal opened={opened} onClose={requestClose} title="Create New Project" size="md">
      <form onSubmit={handleSubmit}>
        <Stack gap="md">
          {messages.length > 0 && (
            <Alert color="red">
              <Stack gap={4}>
                {messages.map((message) => (
                  <div key={message}>{message}</div>
                ))}
              </Stack>
            </Alert>
          )}
          <TextInput
            label="Project Name"
            value={data.name}
            onChange={(e) => setData('name', e.currentTarget.value)}
            required
            disabled={processing}
            maxLength={100}
            error={errors.name}
            data-autofocus
          />
          <Textarea
            label="Description"
            value={data.description}
            onChange={(e) => setData('description', e.currentTarget.value)}
            disabled={processing}
            maxLength={500}
            minRows={3}
          />
          <Group justify="flex-end">
            <Button variant="subtle" onClick={requestClose} disabled={processing}>
              Cancel
            </Button>
            <Button type="submit" loading={processing} disabled={!data.name.trim()}>
              Create
            </Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  );
};
