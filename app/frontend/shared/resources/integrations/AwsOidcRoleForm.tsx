import { Button, Group, NumberInput, Paper, SimpleGrid, Stack, Text, TextInput } from '@mantine/core';
import { useState } from 'react';

import { type AwsOidcRole, type AwsOidcRoleInput, saveAwsOidcRole } from './awsOidcActions';

// AwsOidcRole::DURATIONS
const MIN_DURATION = 900;
const MAX_DURATION = 3600;

type FieldErrors = Partial<Record<keyof AwsOidcRoleInput | 'base', string>>;

const FIELDS: (keyof AwsOidcRoleInput)[] = ['name', 'roleArn', 'region', 'sessionDurationSeconds'];

// Hints of different lengths above the inputs push the two columns' inputs out of line.
const HINT_BELOW: ('label' | 'input' | 'description' | 'error')[] = ['label', 'input', 'description', 'error'];

// Inertia hands back the model's errors with camelized keys; anything not about a field is shown under the form.
const fieldErrors = (errors: Record<string, string>): FieldErrors =>
  Object.entries(errors).reduce<FieldErrors>((acc, [key, message]) => {
    const field = FIELDS.find((f) => f === key) ?? 'base';
    acc[field] = acc[field] ? `${acc[field]} ${message}` : message;
    return acc;
  }, {});

interface Props {
  projectId: number;
  /** The role being edited; null adds one. */
  role: AwsOidcRole | null;
  onDone: () => void;
}

export function AwsOidcRoleForm({ projectId, role, onDone }: Props) {
  const [name, setName] = useState(role?.name ?? '');
  const [roleArn, setRoleArn] = useState(role?.roleArn ?? '');
  const [region, setRegion] = useState(role?.region ?? '');
  const [duration, setDuration] = useState<number | string>(role?.sessionDurationSeconds ?? MAX_DURATION);
  const [errors, setErrors] = useState<FieldErrors>({});
  const [saving, setSaving] = useState(false);

  const submit = () => {
    setErrors({});
    setSaving(true);
    saveAwsOidcRole(
      projectId,
      role?.id ?? null,
      { name, roleArn, region, sessionDurationSeconds: Number(duration) },
      {
        onSuccess: onDone,
        onError: (errs) => setErrors(fieldErrors(errs)),
        onFinish: () => setSaving(false),
      },
    );
  };

  const incomplete = !name.trim() || !roleArn.trim() || !region.trim() || duration === '';

  return (
    <Paper withBorder p="md" radius="md">
      <Stack gap="sm">
        <Text size="sm" fw={600}>
          {role ? `Edit ${role.name}` : 'Add role'}
        </Text>
        <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="sm">
          <TextInput
            inputWrapperOrder={HINT_BELOW}
            label="Name"
            description="The AWS profile name steps use. Lowercase letters, digits and dashes."
            placeholder="prod-diagnose"
            value={name}
            onChange={(e) => setName(e.currentTarget.value)}
            error={errors.name}
            autoFocus
          />
          <TextInput
            inputWrapperOrder={HINT_BELOW}
            label="Role ARN"
            description="The IAM role in your AWS account."
            placeholder="arn:aws:iam::123456789012:role/flow-diagnose"
            value={roleArn}
            onChange={(e) => setRoleArn(e.currentTarget.value)}
            error={errors.roleArn}
          />
          <TextInput
            inputWrapperOrder={HINT_BELOW}
            label="Region"
            description="Where STS is called and the default region for the profile."
            placeholder="eu-west-1"
            value={region}
            onChange={(e) => setRegion(e.currentTarget.value)}
            error={errors.region}
          />
          <NumberInput
            inputWrapperOrder={HINT_BELOW}
            label="Session duration (seconds)"
            description={`From ${MIN_DURATION} to ${MAX_DURATION}. The role's maximum session duration must allow it.`}
            min={MIN_DURATION}
            max={MAX_DURATION}
            step={300}
            allowDecimal={false}
            value={duration}
            onChange={setDuration}
            error={errors.sessionDurationSeconds}
          />
        </SimpleGrid>
        {errors.base && (
          <Text size="sm" c="var(--app-danger-fg)">
            {errors.base}
          </Text>
        )}
        <Group justify="flex-end">
          <Button variant="default" onClick={onDone} disabled={saving}>
            Cancel
          </Button>
          <Button onClick={submit} loading={saving} disabled={incomplete}>
            {role ? 'Save role' : 'Add role'}
          </Button>
        </Group>
      </Stack>
    </Paper>
  );
}
