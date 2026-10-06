import { Head, usePage } from '@inertiajs/react';
import { Alert, Anchor, Badge, Button, Center, Checkbox, Group, List, Paper, Stack, Text, Title } from '@mantine/core';
import { IconBrandTeams, IconDownload, IconFolders } from '@tabler/icons-react';
import { useState } from 'react';

import { postNavigate } from 'shared/lib/postNavigate';
import { Logo, PageShell } from 'shared/ui';

type State = 'expired' | 'pending' | 'connected';

interface Props {
  state: State;
  workspace?: string;
  requestedBy?: { name: string | null; email: string | null };
  organization?: string | null;
  approvedBy?: string | null;
  fileAccess?: boolean | null;
  signInUrl?: string;
  fileAccessUrl?: string;
  packageUrl?: string;
  published?: boolean;
  publishError?: string | null;
}

const Flash = () => {
  const { flash } = usePage<{ flash?: Record<string, unknown> }>().props;
  return (
    <>
      {typeof flash?.alert === 'string' && (
        <Alert color="red" variant="light">
          {flash.alert}
        </Alert>
      )}
      {typeof flash?.notice === 'string' && (
        <Alert color="green" variant="light">
          {flash.notice}
        </Alert>
      )}
    </>
  );
};

const Pending = ({ workspace, requestedBy, signInUrl }: Props) => {
  const [withFiles, setWithFiles] = useState(true);
  return (
    <Stack gap="md">
      <Title order={3} ta="center">
        Connect Microsoft Teams to {workspace}
      </Title>
      <Text size="sm">
        {requestedBy?.name ?? 'Someone'}
        {requestedBy?.email ? ` (${requestedBy.email})` : ''} asked to connect your Microsoft 365 organization to the
        Aixle workspace <strong>{workspace}</strong>. Once it is connected, people in your organization can start that
        workspace&apos;s workflows by mentioning Aixle Flow in Teams.
      </Text>
      <Alert color="yellow" variant="light">
        Approve only if you know this workspace: messages addressed to Aixle Flow in your organization will go to it.
        You need to be a Global, Privileged Role, Cloud Application, Application or Teams Administrator.
      </Alert>
      <Checkbox
        checked={withFiles}
        onChange={(e) => setWithFiles(e.currentTarget.checked)}
        label="Also give access to files shared in Teams"
        description="Lets workflows read the files people attach in channels and save files there. Microsoft offers this only as a permission over all of your organization's files; Aixle opens only the files of messages addressed to it."
      />
      <Button
        onClick={() => signInUrl && postNavigate(signInUrl, { files: withFiles ? '1' : '0' })}
        leftSection={<IconBrandTeams size={18} />}
        fullWidth
      >
        Sign in with Microsoft to approve
      </Button>
    </Stack>
  );
};

const Connected = ({
  workspace,
  organization,
  approvedBy,
  fileAccess,
  fileAccessUrl,
  packageUrl,
  published,
  publishError,
}: Props) => (
  <Stack gap="md">
    <Title order={3} ta="center">
      {organization} is connected to {workspace}
    </Title>
    {approvedBy && (
      <Text size="sm" c="dimmed" ta="center">
        Approved by {approvedBy}
      </Text>
    )}
    <List type="ordered" spacing="md" size="sm">
      <List.Item>
        <Stack gap={6}>
          <Group gap="xs">
            <Text size="sm" fw={500}>
              File access
            </Text>
            <Badge color={fileAccess ? 'green' : 'gray'} variant="light" size="sm">
              {fileAccess ? 'Granted' : 'Not granted'}
            </Badge>
          </Group>
          <Text size="sm" c="dimmed">
            Lets workflows read the files people attach in Teams channels and post files back. Microsoft only offers
            this as a permission over all of your organization&apos;s files; Aixle opens only the files of messages
            addressed to it.
          </Text>
          {!fileAccess && (
            <Button
              onClick={() => fileAccessUrl && postNavigate(fileAccessUrl)}
              variant="default"
              leftSection={<IconFolders size={16} />}
            >
              Grant file access
            </Button>
          )}
        </Stack>
      </List.Item>
      <List.Item>
        <Stack gap={6}>
          <Group gap="xs">
            <Text size="sm" fw={500}>
              Aixle Flow in your organization&apos;s Teams apps
            </Text>
            <Badge color={published ? 'green' : 'gray'} variant="light" size="sm">
              {published ? 'Published' : 'Not published'}
            </Badge>
          </Group>
          <Text size="sm" c="dimmed">
            {published
              ? 'Published when you approved: people in your organization can add it from Teams apps.'
              : publishError === 'forbidden'
                ? 'Your role cannot publish Teams apps. A Teams administrator can upload this file in the Teams admin center: Teams apps → Manage apps → Upload new app.'
                : 'Upload this file in the Teams admin center: Teams apps → Manage apps → Upload new app. Signing in to approve again also publishes it.'}
          </Text>
          {!published && (
            <Button component="a" href={packageUrl} variant="default" leftSection={<IconDownload size={16} />}>
              Download the Teams app
            </Button>
          )}
        </Stack>
      </List.Item>
      <List.Item>
        <Text size="sm">
          Add Aixle Flow to a team or a chat in Teams, then mention it with <code>help</code> to see what it can start.
        </Text>
      </List.Item>
    </List>
  </Stack>
);

function TeamsApproval(props: Props) {
  return (
    <PageShell variant="centered">
      <Head title="Connect Microsoft Teams" />
      <Paper p="xl" radius="md" w="100%" maw={520} withBorder>
        <Center mb={24}>
          <Logo width={96} />
        </Center>
        <Stack gap="md">
          <Flash />
          {props.state === 'expired' && (
            <Stack gap="xs">
              <Title order={3} ta="center">
                This approval link is no longer valid
              </Title>
              <Text size="sm" c="dimmed" ta="center">
                It has expired or was replaced by a newer one. Ask the person who sent it for a new link from Aixle →
                Integrations.
              </Text>
              <Anchor href="/" ta="center" size="sm">
                Go to Aixle Flow
              </Anchor>
            </Stack>
          )}
          {props.state === 'pending' && <Pending {...props} />}
          {props.state === 'connected' && <Connected {...props} />}
        </Stack>
      </Paper>
    </PageShell>
  );
}

export default TeamsApproval;
