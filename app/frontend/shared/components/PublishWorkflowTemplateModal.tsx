import { Modal, Stack, TextInput, Textarea, Select, Group, Button, Text } from '@mantine/core';
import { useForm } from '@mantine/form';
import { zodResolver } from 'mantine-form-zod-resolver';
import { useEffect } from 'react';
import { z } from 'zod';

const publishSchema = z.object({
  name: z.string().min(1, 'Name is required'),
  description: z.string().optional(),
  useCase: z.string().optional(),
  visibility: z.enum(['company', 'private']),
  changelog: z.string().optional(),
});

export type PublishWorkflowTemplateFormValues = z.infer<typeof publishSchema>;

export interface PublishedTemplateMeta {
  templateId: number;
  templateName: string;
  description: string | null;
  useCase: string | null;
  visibility: string;
}

interface Props {
  opened: boolean;
  onClose: () => void;
  mode: 'create' | 'republish';
  initialValues: PublishWorkflowTemplateFormValues;
  loading?: boolean;
  existingTemplate?: PublishedTemplateMeta;
  onSubmit: (values: PublishWorkflowTemplateFormValues) => void;
}

export const PublishWorkflowTemplateModal = ({
  opened,
  onClose,
  mode,
  initialValues,
  loading = false,
  existingTemplate,
  onSubmit,
}: Props) => {
  const form = useForm<PublishWorkflowTemplateFormValues>({
    validate: zodResolver(publishSchema),
    initialValues,
  });

  useEffect(() => {
    if (opened) {
      form.setValues(initialValues);
    }
  }, [opened, initialValues]);

  const isRepublish = mode === 'republish';

  return (
    <Modal
      opened={opened}
      onClose={onClose}
      title={isRepublish ? 'Publish new version' : 'Publish to Catalog'}
      centered
    >
      <form onSubmit={form.onSubmit(onSubmit)}>
        <Stack gap="md">
          {isRepublish && existingTemplate && (
            <Text size="sm" c="dimmed">
              Updating catalog template <strong>{existingTemplate.templateName}</strong>. Existing projects stay on
              their pinned version.
            </Text>
          )}
          <TextInput label="Template name" required disabled={isRepublish} {...form.getInputProps('name')} />
          <Textarea
            label="Description"
            autosize
            minRows={2}
            disabled={isRepublish}
            {...form.getInputProps('description')}
          />
          <TextInput
            label="Use case"
            placeholder="e.g. Feature development, code review pipeline"
            disabled={isRepublish}
            {...form.getInputProps('useCase')}
          />
          <Select
            label="Visibility"
            disabled={isRepublish}
            data={[
              { value: 'company', label: 'Entire company' },
              { value: 'private', label: 'Only me' },
            ]}
            {...form.getInputProps('visibility')}
          />
          {isRepublish && (
            <Textarea
              label="Changelog"
              placeholder="What changed in this version?"
              autosize
              minRows={2}
              {...form.getInputProps('changelog')}
            />
          )}
          <Group justify="flex-end">
            <Button variant="outline" onClick={onClose}>
              Cancel
            </Button>
            <Button type="submit" loading={loading}>
              {isRepublish ? 'Publish version' : 'Publish'}
            </Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  );
};
