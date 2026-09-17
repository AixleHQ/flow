import { Head, useForm } from '@inertiajs/react';
import { Button, Paper, Stack, Text, Title } from '@mantine/core';

import { confirmMagicLinkPath } from 'shared/routes';
import { Logo, PageShell } from 'shared/ui';

interface PageProps {
  token: string;
  [key: string]: unknown;
}

export default function MagicLinkPage({ token }: PageProps) {
  const { post, processing } = useForm({});

  return (
    <PageShell variant="centered">
      <Head title="Sign in" />
      <Paper p="xl" radius="md" w="100%" maw={420}>
        <Stack gap="md">
          <Logo width={96} />
          <Title order={3}>Sign in</Title>
          <Text size="sm" c="dimmed">
            Confirm to finish signing in. The link works once, so nothing has been used up by your mail provider opening
            this page.
          </Text>
          <Button fullWidth size="lg" loading={processing} onClick={() => post(confirmMagicLinkPath(token))}>
            Sign in
          </Button>
        </Stack>
      </Paper>
    </PageShell>
  );
}
