import { router } from '@inertiajs/react';
import { Button, Group, Stack, TextInput, Textarea } from '@mantine/core';
import { useForm } from '@mantine/form';
import { zod4Resolver as zodResolver } from 'mantine-form-zod-resolver';
import { useEffect, useState, type FC } from 'react';
import { z } from 'zod';

import type { Agent } from '@/types/generated';

import { UNSAVED_CHANGES_PROMPT } from 'shared/lib/hooks/useUnsavedChangesGuard';
import { EmojiPicker } from 'shared/ui/EmojiPicker';
import { ResourceDrawer } from 'shared/ui/ResourceDrawer';
import { UnsavedChangesNotice } from 'shared/ui/UnsavedChangesNotice';

const agentSchema = z.object({
  name: z
    .string()
    .min(1, 'Name is required')
    .max(100, 'Name must be at most 100 characters')
    .regex(/^[a-z][a-z0-9_]*$/, 'Must start with letter, use only lowercase letters, numbers, underscores'),
  title: z.string().min(1, 'Title is required').max(200, 'Title must be at most 200 characters'),
  icon: z.string().max(10).optional(),
  persona: z.string().min(1, 'Persona is required').max(5000, 'Persona must be at most 5000 characters'),
  communicationStyle: z.string().max(2000).optional(),
  principles: z.string().max(2000).optional(),
});

type EditableAgent = Pick<Agent, 'id' | 'name' | 'title' | 'icon' | 'persona' | 'communicationStyle' | 'principles'> &
  Partial<Pick<Agent, 'currentVersionNumber'>>;

interface AgentFormModalProps {
  opened: boolean;
  onClose: () => void;
  editAgent?: EditableAgent | null;
  duplicateAgent?: EditableAgent | null;
  basePath: string;
}

export const AgentFormModal: FC<AgentFormModalProps> = ({ opened, onClose, editAgent, duplicateAgent, basePath }) => {
  const [submitting, setSubmitting] = useState(false);
  const isEditMode = !!editAgent;

  const form = useForm({
    validate: zodResolver(agentSchema),
    initialValues: {
      name: '',
      title: '',
      icon: '',
      persona: '',
      communicationStyle: '',
      principles: '',
    },
  });

  useEffect(() => {
    if (opened) {
      if (editAgent) {
        const values = {
          name: editAgent.name,
          title: editAgent.title,
          icon: editAgent.icon || '',
          persona: editAgent.persona,
          communicationStyle: editAgent.communicationStyle || '',
          principles: editAgent.principles || '',
        };
        form.setValues(values);
        form.resetDirty(values);
      } else if (duplicateAgent) {
        form.setValues({
          name: `${duplicateAgent.name}_copy`,
          title: `${duplicateAgent.title} (Copy)`,
          icon: duplicateAgent.icon || '',
          persona: duplicateAgent.persona,
          communicationStyle: duplicateAgent.communicationStyle || '',
          principles: duplicateAgent.principles || '',
        });
      } else {
        form.reset();
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [opened, editAgent, duplicateAgent]);

  const handleSubmit = (values: typeof form.values) => {
    setSubmitting(true);

    const data = { agent: values, baseVersion: editAgent?.currentVersionNumber };

    if (isEditMode && editAgent) {
      router.patch(`${basePath}/${editAgent.id}`, data, {
        preserveScroll: true,
        onSuccess: () => {
          setSubmitting(false);
          onClose();
        },
        onError: (errors) => {
          setSubmitting(false);
          Object.entries(errors).forEach(([key, message]) => {
            form.setFieldError(key, message as string);
          });
        },
      });
    } else {
      router.post(basePath, data, {
        preserveScroll: true,
        onSuccess: () => {
          setSubmitting(false);
          onClose();
        },
        onError: (errors) => {
          setSubmitting(false);
          Object.entries(errors).forEach(([key, message]) => {
            form.setFieldError(key, message as string);
          });
        },
      });
    }
  };

  const handleNameChange = (value: string) => {
    form.setFieldValue('name', value.toLowerCase().replace(/[^a-z0-9_]/g, '_'));
  };

  const unsaved = isEditMode && form.isDirty();
  const handleClose = () => {
    if (unsaved && !window.confirm(UNSAVED_CHANGES_PROMPT)) return;
    onClose();
  };

  return (
    <ResourceDrawer
      opened={opened}
      onClose={handleClose}
      title={isEditMode ? 'Edit Agent' : duplicateAgent ? 'Duplicate Agent' : 'Create Agent'}
      footer={
        <Stack gap="xs">
          <UnsavedChangesNotice visible={unsaved} />
          <Button type="submit" form="agent-form" fullWidth loading={submitting}>
            {isEditMode ? 'Save' : 'Create'}
          </Button>
        </Stack>
      }
    >
      <form id="agent-form" onSubmit={form.onSubmit(handleSubmit)}>
        <Stack gap="md">
          <Group align="flex-start" gap="md">
            <EmojiPicker
              value={form.values.icon}
              onChange={(emoji) => form.setFieldValue('icon', emoji)}
              disabled={submitting}
            />
            <TextInput
              {...form.getInputProps('name')}
              onChange={(e) => handleNameChange(e.currentTarget.value)}
              label="Name"
              placeholder="my_agent"
              description="Unique identifier (lowercase, underscores)"
              style={{ flex: 1 }}
              withAsterisk
              autoFocus
              disabled={isEditMode}
              styles={{
                input: { fontFamily: '"JetBrains Mono", monospace' },
              }}
            />
          </Group>

          <TextInput
            {...form.getInputProps('title')}
            label="Title"
            placeholder="Business Analyst"
            description="Display name for the agent"
            withAsterisk
          />

          <Textarea
            {...form.getInputProps('persona')}
            label="Persona"
            placeholder="Senior analyst with deep expertise in market research..."
            description="Who the agent is, their role and identity"
            minRows={4}
            autosize
            withAsterisk
          />

          <Textarea
            {...form.getInputProps('communicationStyle')}
            label="Communication Style"
            placeholder="Speaks with precision and clarity..."
            description="How the agent communicates (optional)"
            minRows={2}
            autosize
          />

          <Textarea
            {...form.getInputProps('principles')}
            label="Principles"
            placeholder="Ground findings in verifiable evidence..."
            description="Operating principles (optional)"
            minRows={2}
            autosize
          />
        </Stack>
      </form>
    </ResourceDrawer>
  );
};
