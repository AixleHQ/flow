import { Head } from '@inertiajs/react';
import { Anchor, Button, Paper, Stack, Text, Title } from '@mantine/core';

import { loginPath } from 'shared/routes';
import { Logo, PageShell } from 'shared/ui';

// The fulfilment URL AWS Marketplace is given. A buyer never reads this: they
// arrive by POST, which the same path answers with the token exchange. This is
// what a GET gets — AWS fetches the URL and requires a 200 before it will
// accept it, and anyone who keeps the link reaches it too.
const SUBSCRIPTIONS_URL = 'https://aws.amazon.com/marketplace/library';

export default function MarketplaceLandingPage() {
  return (
    <PageShell variant="centered">
      <Head title="AWS Marketplace" />
      <Paper p="xl" radius="md" w="100%" maw={420}>
        <Stack gap="md">
          <Logo width={96} />
          <Title order={3}>Finish setting up from AWS Marketplace</Title>
          <Text size="sm" c="dimmed">
            AWS Marketplace brings you here after you subscribe to Aixle Flow. You&apos;ve opened this page directly, so
            there&apos;s nothing to set up yet.
          </Text>
          <Text size="sm" c="dimmed">
            Open your subscription in AWS Marketplace and choose <b>Set up your account</b>.
          </Text>
          <Button fullWidth size="lg" component="a" href={SUBSCRIPTIONS_URL}>
            Go to AWS Marketplace
          </Button>
          <Text size="sm" c="dimmed">
            Already set up? <Anchor href={loginPath()}>Sign in</Anchor>
          </Text>
        </Stack>
      </Paper>
    </PageShell>
  );
}
