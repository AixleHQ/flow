import { router } from '@inertiajs/react';
import { Anchor, Button, Group, Paper, PasswordInput, Stack, Text, Title } from '@mantine/core';
import { useForm } from '@mantine/form';
import { zod4Resolver } from 'mantine-form-zod-resolver';
import { useState } from 'react';
import { z } from 'zod';

import { formatDateMedium } from 'shared/lib/formatDate';
import { passwordResetsPath, profilePasswordPath } from 'shared/routes';

export interface PasswordState {
  set: boolean;
  changedAt: string | null;
  /** Whether a company this person belongs to takes a password at all. */
  accepted: boolean;
  minLength: number;
}

// The server checks all of this again; these are here so a typo is caught
// before the round trip, worded the same way the server words it.
const buildSchema = (minLength: number, needsCurrent: boolean) =>
  z
    .object({
      currentPassword: needsCurrent ? z.string().min(1, 'Enter your current password.') : z.string(),
      password: z.string().min(1, 'Enter a new password.').min(minLength, `Use at least ${minLength} characters.`),
      passwordConfirmation: z.string(),
    })
    .refine((values) => values.password === values.passwordConfirmation, {
      message: 'The passwords do not match.',
      path: ['passwordConfirmation'],
    });

type FormValues = z.infer<ReturnType<typeof buildSchema>>;

const EMPTY: FormValues = { currentPassword: '', password: '', passwordConfirmation: '' };

function statusLine({ set, changedAt }: PasswordState) {
  if (!set) return 'No password set';
  return changedAt ? `Password set · last changed ${formatDateMedium(changedAt)}` : 'Password set';
}

export function PasswordSection({ password }: { password: PasswordState }) {
  const [open, setOpen] = useState(false);
  const [saving, setSaving] = useState(false);
  const form = useForm<FormValues>({
    initialValues: EMPTY,
    validate: zod4Resolver(buildSchema(password.minLength, password.set)),
  });

  const close = () => {
    form.reset();
    setOpen(false);
  };

  const save = (values: FormValues) => {
    setSaving(true);
    router.patch(profilePasswordPath(), values, {
      preserveScroll: true,
      onError: (errors) => form.setErrors(errors),
      onSuccess: close,
      onFinish: () => setSaving(false),
    });
  };

  const actionLabel = password.set ? 'Change password' : 'Set password';

  return (
    <Paper p="md" radius="md" withBorder>
      <Stack gap="sm">
        <Group justify="space-between">
          <Title order={4}>Password</Title>
          {password.accepted && !open && (
            <Button size="compact-sm" onClick={() => setOpen(true)}>
              {actionLabel}
            </Button>
          )}
        </Group>
        <Text size="sm">{statusLine(password)}</Text>
        {!password.accepted && (
          <Text size="sm" c="dimmed">
            None of your workspaces accepts a password, so there is none to set here. Sign in with one of the methods
            above.
          </Text>
        )}

        {open && (
          <form onSubmit={form.onSubmit(save)} aria-label={actionLabel}>
            <Stack gap="sm" maw={360}>
              {password.set && (
                <PasswordInput
                  label="Current password"
                  autoComplete="current-password"
                  autoFocus
                  {...form.getInputProps('currentPassword')}
                />
              )}
              <PasswordInput
                label="New password"
                description={`At least ${password.minLength} characters.`}
                autoComplete="new-password"
                autoFocus={!password.set}
                {...form.getInputProps('password')}
              />
              <PasswordInput
                label="Confirm password"
                autoComplete="new-password"
                {...form.getInputProps('passwordConfirmation')}
              />
              {password.set && (
                <Anchor
                  component="button"
                  type="button"
                  size="sm"
                  style={{ alignSelf: 'flex-start' }}
                  onClick={() => router.post(passwordResetsPath(), {}, { preserveScroll: true })}
                >
                  Forgot your current password?
                </Anchor>
              )}
              <Group gap="xs">
                <Button type="submit" size="compact-md" loading={saving}>
                  Save password
                </Button>
                <Button size="compact-md" variant="subtle" onClick={close}>
                  Cancel
                </Button>
              </Group>
              <Text size="xs" c="dimmed">
                Saving signs you out on every other device. This one stays signed in.
              </Text>
            </Stack>
          </form>
        )}
      </Stack>
    </Paper>
  );
}
