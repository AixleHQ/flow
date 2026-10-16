import { router } from '@inertiajs/react';
import { Alert, Anchor, Button, Group, List, Stack, Text, TextInput } from '@mantine/core';
import { IconAlertCircle } from '@tabler/icons-react';
import { useState } from 'react';

import { requestJson } from './requestJson';

interface Props {
  basePath: string;
  installUrl: string | null;
  onConnected?: () => void;
  onCancel?: () => void;
}

interface AttachResult {
  connected?: boolean;
  install_required?: boolean;
  install_url?: string | null;
}

const workspaceSlug = (value: string) =>
  value
    .trim()
    .replace(/^https?:\/\/bitbucket\.org\//i, '')
    .split('/')[0];

// The project names the workspace; the server answers either "connected" (the
// company already bound it) or "install the app first". It never says which
// workspaces the company has bound.
export function BitbucketAppConnect({ basePath, installUrl, onConnected, onCancel }: Props) {
  const [workspace, setWorkspace] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [installRequired, setInstallRequired] = useState(false);
  const [installLink, setInstallLink] = useState<string | null>(installUrl);
  const slug = workspaceSlug(workspace);

  const connect = async () => {
    if (!slug) return;
    setError(null);
    setSubmitting(true);
    try {
      const result = (await requestJson(
        `${basePath}/bitbucket_attach`,
        { method: 'POST', body: JSON.stringify({ workspace: slug }) },
        'Bitbucket refused the connection',
      )) as AttachResult;
      if (result.connected) {
        router.reload();
        onConnected?.();
      } else if (result.install_required) {
        setInstallLink(result.install_url ?? installUrl);
        setInstallRequired(true);
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Bitbucket refused the connection');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Stack gap="sm">
      <Text size="sm" c="dimmed">
        The Aixle Flow app gives this project a bot on your Bitbucket workspace and short-lived tokens. Nobody pastes a
        credential, and removing the app in Bitbucket ends the access.
      </Text>
      <TextInput
        label="Bitbucket workspace"
        description="The workspace ID in bitbucket.org/<workspace>."
        placeholder="acme"
        value={workspace}
        onChange={(event) => {
          setWorkspace(event.currentTarget.value);
          setInstallRequired(false);
        }}
        onKeyDown={(event) => {
          if (event.key === 'Enter') void connect();
        }}
        autoComplete="off"
        spellCheck={false}
      />
      {error && (
        <Alert color="red" icon={<IconAlertCircle size={16} />}>
          {error}
        </Alert>
      )}
      {installRequired && (
        <Alert color="blue" title="Install the app on the workspace first">
          <List type="ordered" size="sm" spacing={4}>
            <List.Item>
              {installLink ? (
                <>
                  A workspace administrator installs{' '}
                  <Anchor href={installLink} target="_blank" rel="noopener noreferrer">
                    Aixle Flow
                  </Anchor>{' '}
                  on <strong>{slug}</strong>.
                </>
              ) : (
                <>
                  This Aixle has no install link: ask the people who run it to install Aixle Flow on{' '}
                  <strong>{slug}</strong>.
                </>
              )}
            </List.Item>
            <List.Item>In Bitbucket, they open Workspace settings → Aixle Flow and press Connect.</List.Item>
            <List.Item>Aixle opens a page to confirm this project. The connection then appears here.</List.Item>
          </List>
        </Alert>
      )}
      <Group justify="flex-end">
        {onCancel && (
          <Button variant="default" onClick={onCancel}>
            Cancel
          </Button>
        )}
        <Button onClick={() => void connect()} loading={submitting} disabled={!slug}>
          Connect
        </Button>
      </Group>
    </Stack>
  );
}
