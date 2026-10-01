import { router, usePage } from '@inertiajs/react';
import { Alert, Button, Checkbox, Select, Stack, TextInput } from '@mantine/core';
import { useForm } from '@mantine/form';
import { zod4Resolver as zodResolver } from 'mantine-form-zod-resolver';
import { useEffect, useMemo, useState } from 'react';
import { z } from 'zod';

import { useConfirmClose } from 'shared/lib/hooks/useConfirmClose';
import { ResourceDrawer } from 'shared/ui/ResourceDrawer';

export interface AvailableScopeGroup {
  integrationId: number;
  integrationName: string;
  provider: string;
  scopes: { id: string; name: string }[];
}

interface Props {
  opened: boolean;
  onClose: () => void;
  basePath: string;
  availableScopes: AvailableScopeGroup[];
}

export const HANDLE_FORMAT = /^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$/;

const schema = z.object({
  integrationId: z.string().min(1, 'Pick a connection'),
  externalScopeId: z.string().min(1, 'Pick a project'),
  handle: z.string().refine((v) => v === '' || HANDLE_FORMAT.test(v), 'Lowercase letters, digits and dashes'),
  readOnly: z.boolean(),
  primary: z.boolean(),
});
type FormData = z.infer<typeof schema>;

const EMPTY_VALUES: FormData = { integrationId: '', externalScopeId: '', handle: '', readOnly: false, primary: false };

const suggestHandle = (name: string) =>
  name
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60);

export const AddTrackerDrawer = ({ opened, onClose, basePath, availableScopes }: Props) => {
  const errors = usePage().props.errors as Record<string, string> | undefined;
  const [loading, setLoading] = useState(false);
  const form = useForm<FormData>({
    validate: zodResolver(schema),
    initialValues: EMPTY_VALUES,
  });

  useEffect(() => {
    if (!opened) return;
    form.setInitialValues(
      availableScopes.length === 1
        ? { ...EMPTY_VALUES, integrationId: String(availableScopes[0].integrationId) }
        : EMPTY_VALUES,
    );
    form.reset();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [opened]);

  const group = useMemo(
    () => availableScopes.find((g) => String(g.integrationId) === form.values.integrationId),
    [availableScopes, form.values.integrationId],
  );

  const pickScope = (scopeId: string | null) => {
    form.setFieldValue('externalScopeId', scopeId ?? '');
    const scope = group?.scopes.find((s) => s.id === scopeId);
    if (scope && !form.isDirty('handle')) form.setFieldValue('handle', suggestHandle(scope.name));
  };

  const handleSubmit = (values: FormData) => {
    setLoading(true);
    router.post(
      basePath,
      {
        tracker: {
          integrationId: values.integrationId,
          externalScopeId: values.externalScopeId,
          handle: values.handle,
          access: values.readOnly ? 'read_only' : 'read_write',
          primary: values.primary,
        },
      },
      { preserveScroll: true, onSuccess: () => onClose(), onFinish: () => setLoading(false) },
    );
  };

  const serverError = errors && Object.values(errors)[0];
  const requestClose = useConfirmClose(form.isDirty(), onClose);

  return (
    <ResourceDrawer
      opened={opened}
      onClose={requestClose}
      title="Add tracker"
      footer={
        <Button type="submit" form="add-tracker-form" fullWidth loading={loading}>
          Add tracker
        </Button>
      }
    >
      <form id="add-tracker-form" onSubmit={form.onSubmit(handleSubmit)}>
        <Stack gap="md">
          {serverError && <Alert color="red">{serverError}</Alert>}
          <Select
            label="Connection"
            placeholder="Select connection..."
            data={availableScopes.map((g) => ({ value: String(g.integrationId), label: g.integrationName }))}
            allowDeselect={false}
            {...form.getInputProps('integrationId')}
            onChange={(value) => {
              form.setFieldValue('integrationId', value ?? '');
              form.setFieldValue('externalScopeId', '');
            }}
            withAsterisk
          />
          <Select
            label="Project"
            placeholder="Select project..."
            data={(group?.scopes ?? []).map((s) => ({ value: s.id, label: s.name }))}
            disabled={!group}
            allowDeselect={false}
            {...form.getInputProps('externalScopeId')}
            onChange={pickScope}
            withAsterisk
          />
          <TextInput
            label="Handle"
            description="What agents and triggers call this tracker. Suggested from the project name."
            placeholder="customer-platform"
            {...form.getInputProps('handle')}
          />
          <Checkbox
            label="Read-only"
            description="Agents can read issues but not change them."
            {...form.getInputProps('readOnly', { type: 'checkbox' })}
          />
          <Checkbox
            label="Primary tracker"
            description="Where agents file issues when a call names no tracker."
            {...form.getInputProps('primary', { type: 'checkbox' })}
          />
        </Stack>
      </form>
    </ResourceDrawer>
  );
};
