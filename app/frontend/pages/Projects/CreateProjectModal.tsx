import { useForm } from '@inertiajs/react';
import { Alert, Button, Group, Modal, Select, Stack, Text, TextInput, Textarea } from '@mantine/core';

import { companyProjectsPath } from 'shared/routes';

interface WorkflowTemplateOption {
  id: number;
  name: string;
  description: string | null;
  useCase: string | null;
  currentVersionId: number | null;
  stepsCount: number;
}

interface CreateProjectModalProps {
  opened: boolean;
  onClose: () => void;
  workflowTemplates?: WorkflowTemplateOption[];
}

export const CreateProjectModal = ({ opened, onClose, workflowTemplates = [] }: CreateProjectModalProps) => {
  const { data, setData, post, processing, errors, reset, clearErrors, transform } = useForm({
    name: '',
    description: '',
    workflowTemplateVersionId: '' as string | number,
  });

  const selectedTemplate = workflowTemplates.find(
    (t) => String(t.currentVersionId) === String(data.workflowTemplateVersionId),
  );

  const handleClose = () => {
    reset();
    clearErrors();
    onClose();
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    transform((d) => ({
      project: {
        name: d.name,
        description: d.description,
        workflowTemplateVersionId: d.workflowTemplateVersionId || undefined,
      },
    }));
    post(companyProjectsPath(), {
      onSuccess: handleClose,
    });
  };

  const templateOptions = workflowTemplates
    .filter((t) => t.currentVersionId)
    .map((t) => ({
      value: String(t.currentVersionId),
      label: t.name,
    }));

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
          {templateOptions.length > 0 && (
            <>
              <Select
                label="Start from template"
                placeholder="Blank project"
                clearable
                data={templateOptions}
                value={data.workflowTemplateVersionId ? String(data.workflowTemplateVersionId) : null}
                onChange={(value) => setData('workflowTemplateVersionId', value ?? '')}
                disabled={processing}
              />
              {selectedTemplate && (
                <Text size="sm" c="dimmed">
                  {selectedTemplate.description ||
                    selectedTemplate.useCase ||
                    `${selectedTemplate.stepsCount} workflow steps`}
                </Text>
              )}
            </>
          )}
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
