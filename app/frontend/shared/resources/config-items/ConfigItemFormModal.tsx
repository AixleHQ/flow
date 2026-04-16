import { router } from '@inertiajs/react';
import { Button, Group, Modal, PasswordInput, Select, Stack, Textarea, TextInput } from '@mantine/core';
import { useForm } from '@mantine/form';
import { zodResolver } from 'mantine-form-zod-resolver';
import { useEffect, useState, type FC } from 'react';
import { z } from 'zod';

const createSchema = z.object({
  name: z.string().min(1, 'Name is required'),
  value: z.string().min(1, 'Value is required'),
  description: z.string().optional(),
  itemType: z.string().min(1, 'Type is required'),
});

const editSchema = z.object({
  name: z.string().min(1, 'Name is required'),
  value: z.string().optional(),
  description: z.string().optional(),
  itemType: z.string().min(1, 'Type is required'),
});

type FormData = z.infer<typeof createSchema>;

interface ConfigItem {
  id: number;
  name: string;
  value: string;
  description: string | null;
  itemType: string;
}

interface Props {
  opened: boolean;
  onClose: () => void;
  item?: ConfigItem | null;
  basePath: string;
}

const TYPE_OPTIONS = [
  { value: 'variable', label: 'Variable' },
  { value: 'secret', label: 'Secret' },
];

export const ConfigItemFormModal: FC<Props> = ({ opened, onClose, item, basePath }) => {
  const [loading, setLoading] = useState(false);
  const isEditing = !!item;

  const form = useForm<FormData>({
    validate: zodResolver(isEditing ? editSchema : createSchema),
    initialValues: {
      name: '',
      value: '',
      description: '',
      itemType: 'variable',
    },
  });

  useEffect(() => {
    if (opened) {
      if (item) {
        form.setValues({
          name: item.name,
          value: '',
          description: item.description ?? '',
          itemType: item.itemType,
        });
      } else {
        form.reset();
      }
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [opened, item]);

  const handleSubmit = (values: FormData) => {
    setLoading(true);

    const opts = {
      preserveScroll: true,
      onFinish: () => setLoading(false),
      onSuccess: () => onClose(),
    };

    if (isEditing) {
      router.patch(`${basePath}/${item!.id}`, { configItem: values }, opts);
    } else {
      router.post(basePath, { configItem: values }, opts);
    }
  };

  return (
    <Modal opened={opened} onClose={onClose} title={isEditing ? 'Edit Config Item' : 'Add Config Item'} centered>
      <form onSubmit={form.onSubmit(handleSubmit)}>
        <Stack gap="md">
          <TextInput
            label="Name"
            placeholder="API_KEY"
            description="Uppercase with underscores (e.g., API_KEY)"
            {...form.getInputProps('name')}
            onChange={(e) =>
              form.setFieldValue('name', e.currentTarget.value.toUpperCase().replace(/[^A-Z0-9_]/g, '_'))
            }
            disabled={isEditing}
            required
            ff="monospace"
          />
          <Select label="Type" data={TYPE_OPTIONS} {...form.getInputProps('itemType')} disabled={isEditing} />
          {form.values.itemType === 'secret' ? (
            <PasswordInput
              label={isEditing ? 'New Value (leave empty to keep current)' : 'Value'}
              placeholder="Enter secret value..."
              {...form.getInputProps('value')}
              required={!isEditing}
            />
          ) : (
            <TextInput
              label="Value"
              placeholder="Enter value..."
              {...form.getInputProps('value')}
              required={!isEditing}
            />
          )}
          <Textarea label="Description" placeholder="Optional description..." {...form.getInputProps('description')} />
          <Group justify="flex-end" mt="sm">
            <Button variant="default" onClick={onClose} disabled={loading}>
              Cancel
            </Button>
            <Button type="submit" loading={loading}>
              {isEditing ? 'Update' : 'Create'}
            </Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  );
};
