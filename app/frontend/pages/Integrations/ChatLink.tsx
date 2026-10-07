import { Head } from '@inertiajs/react';
import { Anchor, Button, Center, Paper, Stack, Text, Title } from '@mantine/core';
import type { ReactNode } from 'react';

import { postNavigate } from 'shared/lib/postNavigate';
import { Logo, PageShell } from 'shared/ui';
import { IntegrationLogo } from 'shared/ui/IntegrationLogo';

import { Flash } from './Flash';

type State = 'expired' | 'sign_in' | 'other_company' | 'ready' | 'linked';

interface Props {
  state: State;
  // The messenger whose account is being linked, and the sign-in that proves it.
  provider: 'teams' | 'slack';
  messenger: string;
  signInLabel: string;
  account?: { name: string | null; email: string | null } | null;
  workspace?: string;
  signInUrl?: string;
  loginUrl?: string;
}

const Message = ({ title, children }: { title: string; children: ReactNode }) => (
  <Stack gap="xs">
    <Title order={3} ta="center">
      {title}
    </Title>
    <Text size="sm" c="dimmed" ta="center">
      {children}
    </Text>
  </Stack>
);

function ChatLink({ state, provider, messenger, signInLabel, account, workspace, signInUrl, loginUrl }: Props) {
  return (
    <PageShell variant="centered">
      <Head title={`Link your ${messenger} account`} />
      <Paper p="xl" radius="md" w="100%" maw={520} withBorder>
        <Center mb={24}>
          <Logo width={96} />
        </Center>
        <Stack gap="md">
          <Flash />
          {state === 'expired' && (
            <Message title="This link is no longer valid">
              It expires an hour after Aixle Flow sends it. Ask Aixle Flow in {messenger} again for a new one.
            </Message>
          )}
          {state === 'sign_in' && (
            <>
              <Message title="Sign in to Aixle first">
                Sign in to your Aixle account, then open the link from {messenger} again.
              </Message>
              <Button component="a" href={loginUrl} fullWidth>
                Sign in to Aixle
              </Button>
            </>
          )}
          {state === 'other_company' && (
            <Message title={`Switch to ${workspace}`}>
              This {messenger} workspace is connected to the Aixle workspace {workspace}. Switch to it, then open the
              link again.
            </Message>
          )}
          {state === 'ready' && (
            <>
              <Title order={3} ta="center">
                Link your {messenger} account
              </Title>
              <Text size="sm">
                Aixle Flow in {messenger} will start {workspace} workflows as <strong>{account?.name}</strong>
                {account?.email ? ` (${account.email})` : ''}, with what this account may run. Sign in with the account
                you use in {messenger} to prove it is yours. This does not add a way to sign in to Aixle.
              </Text>
              <Button
                variant="default"
                onClick={() => signInUrl && postNavigate(signInUrl)}
                leftSection={<IntegrationLogo provider={provider} size={18} />}
                fullWidth
              >
                {signInLabel}
              </Button>
            </>
          )}
          {state === 'linked' && (
            <Message title={`Your ${messenger} account is linked`}>
              Aixle Flow in {messenger} knows you as {account?.name}. Go back to {messenger} and run the workflow again.
            </Message>
          )}
          {state !== 'ready' && (
            <Anchor href="/" ta="center" size="sm">
              Go to Aixle Flow
            </Anchor>
          )}
        </Stack>
      </Paper>
    </PageShell>
  );
}

export default ChatLink;
