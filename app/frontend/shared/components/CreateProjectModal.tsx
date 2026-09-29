import { useForm } from '@inertiajs/react';
import { Alert, Button, Group, Modal, Stack, TextInput, Textarea } from '@mantine/core';

interface CreateProjectModalProps {
  opened: boolean;
  onClose: () => void;
}

export const CreateProjectModal = ({ opened, onClose }: CreateProjectModalProps) => {
  const { data, setData, post, processing, errors, reset, clearErrors, transform } = useForm({
    name: '',
    description: '',
  });

  const handleClose = () => {
    reset();
    clearErrors();
    onClose();
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    transform((d) => ({ project: d }));
    post('/company/projects', {
      onSuccess: handleClose,
    });
  };

  return (
    <Modal opened={opened} onClose={handleClose} title="Create New Project" size="md">
      <form onSubmit={handleSubmit}>
        <Stack gap="md">
          {errors.name && (
            <Alert color="red" onClose={() => clearErrors('name')}>
              {errors.name}
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
            <Button variant="subtle" onClick={handleClose} disabled={processing}>
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
