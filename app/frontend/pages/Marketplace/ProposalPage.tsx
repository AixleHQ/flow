import { Head, useForm } from '@inertiajs/react';
import { Button, Paper, Stack, Text, Title } from '@mantine/core';

import { confirmMarketplaceProposalPath } from 'shared/routes';
import { Logo, PageShell } from 'shared/ui';

interface PageProps {
  token: string;
  email: string;
  [key: string]: unknown;
}

// The link from the "confirm your request" mail. Like the magic-link page, the
// GET that drew this proves nothing: mail scanners open every link, and the
// request is raised only by the button.
export default function MarketplaceProposalPage({ token, email }: PageProps) {
  const { post, processing } = useForm({ token });
  const domain = email.split('@')[1] ?? '';

  return (
    <PageShell variant="centered">
      <Head title="Confirm your request" />
      <Paper p="xl" radius="md" w="100%" maw={420}>
        <Stack gap="md">
          <Logo width={96} />
          <Title order={3}>Confirm your request</Title>
          <Text size="sm" c="dimmed">
            Confirming proves that <b>{email}</b> is yours and asks the administrators of the workspace at{' '}
            <b>{domain}</b> to apply your AWS Marketplace subscription to it. Nobody has been asked anything yet.
          </Text>
          <Text size="sm" c="dimmed">
            If you are an administrator there yourself, you will be asked to sign in and can decide right away.
          </Text>
          <Button fullWidth size="lg" loading={processing} onClick={() => post(confirmMarketplaceProposalPath())}>
            Confirm the request
          </Button>
        </Stack>
      </Paper>
    </PageShell>
  );
}
