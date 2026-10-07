import { Head } from '@inertiajs/react';
import { Anchor, Button, Center, Paper, Stack, Text, Title } from '@mantine/core';
import { IconBrandTeams } from '@tabler/icons-react';
import type { ReactNode } from 'react';

import { postNavigate } from 'shared/lib/postNavigate';
import { Logo, PageShell } from 'shared/ui';

import { Flash } from './Flash';

type State = 'expired' | 'sign_in' | 'other_company' | 'ready' | 'linked';

interface Props {
  state: State;
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

function TeamsLink({ state, account, workspace, signInUrl, loginUrl }: Props) {
  return (
    <PageShell variant="centered">
      <Head title="Link your Teams account" />
      <Paper p="xl" radius="md" w="100%" maw={520} withBorder>
        <Center mb={24}>
          <Logo width={96} />
        </Center>
        <Stack gap="md">
          <Flash />
          {state === 'expired' && (
            <Message title="This link is no longer valid">
              It expires an hour after Aixle Flow sends it. Ask Aixle Flow in Teams again for a new one.
            </Message>
          )}
          {state === 'sign_in' && (
            <>
              <Message title="Sign in to Aixle first">
                Sign in to your Aixle account, then open the link from Teams again.
              </Message>
              <Button component="a" href={loginUrl} fullWidth>
                Sign in to Aixle
              </Button>
            </>
          )}
          {state === 'other_company' && (
            <Message title={`Switch to ${workspace}`}>
              This Teams organization is connected to the Aixle workspace {workspace}. Switch to it, then open the link
              again.
            </Message>
          )}
          {state === 'ready' && (
            <>
              <Title order={3} ta="center">
                Link your Teams account
              </Title>
              <Text size="sm">
                Aixle Flow in Teams will start {workspace} workflows as <strong>{account?.name}</strong>
                {account?.email ? ` (${account.email})` : ''}, with what this account may run. Sign in with the
                Microsoft account you use in Teams to prove it is yours. This does not add a way to sign in to Aixle.
              </Text>
              <Button
                onClick={() => signInUrl && postNavigate(signInUrl)}
                leftSection={<IconBrandTeams size={18} />}
                fullWidth
              >
                Sign in with Microsoft to link
              </Button>
            </>
          )}
          {state === 'linked' && (
            <Message title="Your Teams account is linked">
              Aixle Flow in Teams knows you as {account?.name}. Go back to Teams and run the workflow again.
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

export default TeamsLink;
