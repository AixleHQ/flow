import { Head } from '@inertiajs/react';
import { Alert, Anchor, Button, Center, Group, List, Paper, Stack, Text, Title } from '@mantine/core';
import { IconAlertTriangle } from '@tabler/icons-react';
import type { ReactNode } from 'react';

import { postNavigate } from 'shared/lib/postNavigate';
import { Logo, PageShell } from 'shared/ui';

type State = 'ready' | 'no_company' | 'invalid' | 'impersonating';

interface Props {
  state: State;
  message?: string | null;
  // `host` is set only when the app identified itself by a metadata document URL —
  // the one part of its identity that is not self-asserted.
  client?: { name: string | null; host: string | null; label: string; verified: boolean };
  destination?: string;
  onThisComputer?: boolean;
  account?: { name: string | null; email: string };
  companies?: string[];
  excludedCompanies?: string[];
  authorizeUrl?: string;
  authorizeParams?: Record<string, string>;
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

function McpAuthorize({
  state,
  message,
  client,
  destination,
  onThisComputer,
  account,
  companies = [],
  excludedCompanies = [],
  authorizeUrl,
  authorizeParams = {},
}: Props) {
  const decide = (decision: 'allow' | 'deny') =>
    authorizeUrl && postNavigate(authorizeUrl, { ...authorizeParams, decision });

  return (
    <PageShell variant="centered">
      <Head title="Connect an app to Aixle" />
      <Paper p="xl" radius="md" w="100%" maw={520} withBorder>
        <Center mb={24}>
          <Logo width={96} />
        </Center>
        <Stack gap="md">
          {state === 'invalid' && <Message title="This app cannot connect">{message}</Message>}
          {state === 'impersonating' && (
            <Message title="Not while impersonating">
              An app cannot be connected to someone else&apos;s account. Stop impersonating, then connect it as
              yourself.
            </Message>
          )}
          {state === 'no_company' && excludedCompanies.length === 0 && (
            <Message title="No company to connect to">
              You are not an active member of any company in Aixle yet.
            </Message>
          )}
          {state === 'no_company' && excludedCompanies.length > 0 && (
            <Message title="Sign in the way your company requires">
              {excludedCompanies.join(', ')} {excludedCompanies.length === 1 ? 'requires' : 'require'} a different
              sign-in method than the one you used. Sign out, sign in with it, then connect the app again.
            </Message>
          )}
          {state === 'ready' && client && (
            <>
              <Title order={3} ta="center">
                Connect {client.label} to Aixle
              </Title>
              <Text size="sm">
                {client.label} will use Aixle as <strong>{account?.name ?? account?.email}</strong>
                {account?.name ? ` (${account.email})` : ''}: list your projects, manage board tasks and build
                workflows, with exactly the access you have.
              </Text>
              {!client.verified && (
                <Alert color="yellow" variant="light" icon={<IconAlertTriangle size={16} />}>
                  Aixle cannot verify this app. &ldquo;{client.label}&rdquo; is the name it gave itself.
                </Alert>
              )}
              <div>
                <Text size="sm" fw={600}>
                  In {companies.length === 1 ? 'this company' : 'these companies'}:
                </Text>
                <List size="sm">
                  {companies.map((name) => (
                    <List.Item key={name}>{name}</List.Item>
                  ))}
                </List>
                {excludedCompanies.length > 0 && (
                  <Text size="xs" c="dimmed" mt={4}>
                    Not {excludedCompanies.join(', ')}:{' '}
                    {excludedCompanies.length === 1 ? 'it requires' : 'they require'} a different sign-in method than
                    the one you used.
                  </Text>
                )}
              </div>
              <Text size="sm" c="dimmed">
                After you allow it, your browser goes back to <strong>{destination}</strong>.
                {onThisComputer && ' Only allow this if you started connecting from an app on this computer.'}
              </Text>
              <Group grow>
                <Button variant="default" onClick={() => decide('deny')}>
                  Deny
                </Button>
                <Button onClick={() => decide('allow')}>Allow</Button>
              </Group>
              <Text size="xs" c="dimmed" ta="center">
                You can disconnect it at any time in your profile, under Personal MCP.
              </Text>
            </>
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

export default McpAuthorize;
