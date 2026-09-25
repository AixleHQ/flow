import { Head, useForm, usePage } from '@inertiajs/react';
import { Button, Center, NumberInput, Paper, Stack, Text, TextInput, Title } from '@mantine/core';

import { workspacePath } from 'shared/routes';
import { Logo, PageShell } from 'shared/ui';

interface PageProps {
  suggestedDomain: string;
  suggestedName: string | null;
  defaultMaxSessions: number;
  errors?: Record<string, string>;
  [key: string]: unknown;
}

const NewWorkspacePage = () => {
  const { suggestedDomain, suggestedName, defaultMaxSessions, errors } = usePage<PageProps>().props;

  const form = useForm({
    name: suggestedName ?? '',
    email_domain: suggestedDomain,
    max_sessions: String(defaultMaxSessions),
  });

  const submit = (event: React.FormEvent) => {
    event.preventDefault();
    form.post(workspacePath());
  };

  return (
    <PageShell>
      <Head title="Create your workspace" />
      <Center mih="100vh" px="md">
        <Paper withBorder p="xl" radius="md" w="100%" maw={440}>
          <Stack gap="lg">
            <Stack gap={6} align="center">
              <Logo />
              <Title order={2} fz="h3" ta="center">
                Create your workspace
              </Title>
              <Text c="dimmed" fz="sm" ta="center">
                Nobody has claimed {suggestedDomain} yet, so this one is yours to start.
              </Text>
            </Stack>

            <form onSubmit={submit}>
              <Stack gap="md">
                <TextInput
                  label="Workspace name"
                  placeholder="Acme Robotics"
                  required
                  value={form.data.name}
                  onChange={(event) => form.setData('name', event.currentTarget.value)}
                  error={form.errors.name || errors?.name}
                />
                <TextInput
                  label="Email domain"
                  description="Everyone signing in with an address here joins this workspace."
                  required
                  value={form.data.email_domain}
                  onChange={(event) => form.setData('email_domain', event.currentTarget.value)}
                  error={form.errors.email_domain || errors?.email_domain}
                />
                <NumberInput
                  label="Concurrent sessions"
                  description="How many sessions this workspace may run at once. You can change it later in settings."
                  min={1}
                  allowDecimal={false}
                  allowNegative={false}
                  required
                  value={form.data.max_sessions}
                  onChange={(value) => form.setData('max_sessions', value === '' || value == null ? '' : String(value))}
                  error={form.errors.max_sessions || errors?.max_sessions}
                />
                <Button type="submit" loading={form.processing} fullWidth mt="xs">
                  Create workspace
                </Button>
              </Stack>
            </form>
          </Stack>
        </Paper>
      </Center>
    </PageShell>
  );
};

export default NewWorkspacePage;
