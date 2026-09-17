import { Head } from '@inertiajs/react';
import { Button, Paper, Stack, Text, Title } from '@mantine/core';

import { oidcStartPath } from 'shared/routes';
import { Logo, PageShell } from 'shared/ui';

interface Connection {
  id: number;
  name: string;
}

interface PageProps {
  companyName: string;
  connections: Connection[];
  [key: string]: unknown;
}

function getCsrfToken(): string {
  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? '';
}

export default function SsoChoicePage({ companyName, connections }: PageProps) {
  return (
    <PageShell>
      <Head title="Choose a sign-in method" />
      <Paper p="xl" radius="md" w="100%" maw={420}>
        <Stack gap="md">
          <Logo width={96} />
          <Title order={3}>Sign in to {companyName}</Title>
          <Text size="sm" c="dimmed">
            This workspace has more than one identity provider. Pick the one you use.
          </Text>
          {connections.map((connection) => (
            <form key={connection.id} method="post" action={oidcStartPath(connection.id)}>
              <input type="hidden" name="authenticity_token" value={getCsrfToken()} />
              <Button type="submit" variant="default" fullWidth size="lg">
                {connection.name}
              </Button>
            </form>
          ))}
        </Stack>
      </Paper>
    </PageShell>
  );
}
