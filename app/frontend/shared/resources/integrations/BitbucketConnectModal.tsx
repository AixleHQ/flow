import { router } from '@inertiajs/react';
import { Alert, Code, Group, Modal, PasswordInput, Radio, Stack, Text, TextInput, Button } from '@mantine/core';
import { IconAlertCircle } from '@tabler/icons-react';
import { useCallback, useEffect, useState } from 'react';

import { useConfirmClose } from 'shared/lib/hooks/useConfirmClose';

import { BitbucketAppConnect } from './BitbucketAppConnect';

export interface BitbucketProps {
  /** False on a deployment with no registered Forge app (BITBUCKET_FORGE_* unset). */
  appModeEnabled: boolean;
  /** The app's sharing link; null unless app mode is enabled. */
  installUrl: string | null;
}

interface Props {
  opened: boolean;
  onClose: () => void;
  basePath: string;
  bitbucket?: BitbucketProps;
}

type AuthMode = 'app' | 'token';

interface FieldErrors {
  workspace?: string;
  token?: string;
}

const fieldErrors = (errors: unknown): FieldErrors => {
  if (typeof errors !== 'object' || !errors) return { token: 'Failed to connect Bitbucket' };
  const raw = errors as Record<string, unknown>;
  const text = (value: unknown) =>
    typeof value === 'string' ? value : Array.isArray(value) ? value.join(' ') : undefined;
  const result = { workspace: text(raw.workspace), token: text(raw.token) };
  return result.workspace || result.token ? result : { token: Object.values(raw).map(String).join(' ') };
};

export const BitbucketConnectModal = ({ opened, onClose, basePath, bitbucket }: Props) => {
  const appModeEnabled = bitbucket?.appModeEnabled ?? false;
  const defaultMode: AuthMode = appModeEnabled ? 'app' : 'token';
  const [authMode, setAuthMode] = useState<AuthMode>(defaultMode);
  const [workspace, setWorkspace] = useState('');
  const [token, setToken] = useState('');
  const [loading, setLoading] = useState(false);
  const [errors, setErrors] = useState<FieldErrors>({});

  useEffect(() => {
    if (opened) setAuthMode(defaultMode);
  }, [opened, defaultMode]);

  const close = useCallback(() => {
    onClose();
    setWorkspace('');
    setToken('');
    setErrors({});
  }, [onClose]);

  const requestClose = useConfirmClose(workspace !== '' || token !== '', close);

  // Only this branch posts a token, so switching modes can never submit one
  // the other path collected.
  const connectToken = useCallback(() => {
    const slug = workspace.trim();
    const secret = token.trim();
    if (!slug || !secret) return;

    setErrors({});
    setLoading(true);
    router.post(
      basePath,
      { provider: 'bitbucket', workspace: slug, token: secret },
      {
        preserveScroll: true,
        onSuccess: () => close(),
        onError: (received) => setErrors(fieldErrors(received)),
        onFinish: () => setLoading(false),
      },
    );
  }, [basePath, close, token, workspace]);

  return (
    <Modal opened={opened} onClose={requestClose} title="Connect Bitbucket" centered size="lg">
      <Stack gap="md">
        <Radio.Group value={authMode} onChange={(value) => setAuthMode(value as AuthMode)}>
          <Stack gap="sm">
            <Radio
              value="app"
              disabled={!appModeEnabled}
              label="Install the Aixle Flow app on the workspace (Recommended)"
              description={
                appModeEnabled
                  ? 'Aixle acts as the app, not as a person: short-lived tokens it holds itself, and Bitbucket events that close CI gates the moment a build finishes.'
                  : 'Unavailable on this deployment — no Forge app is registered (BITBUCKET_FORGE_APP_ID and BITBUCKET_FORGE_ENVIRONMENT_ID).'
              }
            />
            <Radio
              value="token"
              label="Paste an access token or API token"
              description="For a workspace without the app, or a deployment that has none. CI gates resolve by polling."
            />
          </Stack>
        </Radio.Group>

        {authMode === 'app' ? (
          <BitbucketAppConnect
            basePath={basePath}
            installUrl={bitbucket?.installUrl ?? null}
            onConnected={close}
            onCancel={requestClose}
          />
        ) : (
          <>
            <TextInput
              label="Workspace"
              description="The workspace ID in bitbucket.org/<workspace>."
              placeholder="acme"
              value={workspace}
              onChange={(e) => setWorkspace(e.currentTarget.value)}
              error={errors.workspace}
              autoFocus
            />
            <PasswordInput
              label="Token"
              description="Stored encrypted. It is never shown again — to change it, paste a new one."
              value={token}
              onChange={(e) => setToken(e.currentTarget.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') connectToken();
              }}
              error={errors.token}
            />
            <Text size="sm" c="dimmed">
              <b>Access token</b> (workspace, project or repository settings → Access tokens): a bot, not a person, and
              nothing breaks when someone leaves. Workspace and project tokens need the Premium plan; a repository token
              reaches only its repository.
            </Text>
            <Text size="sm" c="dimmed">
              <b>API token with scopes</b> (Atlassian account → Security → API tokens): acts as you, expires within a
              year. Grant Bitbucket <Code>read:repository</Code>, <Code>write:repository</Code>,{' '}
              <Code>read:pullrequest</Code>, <Code>write:pullrequest</Code>, <Code>read:pipeline</Code>,{' '}
              <Code>read:workspace</Code> and <Code>read:user</Code> — write does not include read.
            </Text>
            {(errors.workspace || errors.token) && (
              <Alert color="red" icon={<IconAlertCircle size={16} />}>
                {[errors.workspace, errors.token].filter(Boolean).join(' ')}
              </Alert>
            )}
            <Group justify="flex-end">
              <Button variant="default" onClick={requestClose}>
                Cancel
              </Button>
              <Button onClick={connectToken} loading={loading} disabled={!workspace.trim() || !token.trim()}>
                Connect
              </Button>
            </Group>
          </>
        )}
      </Stack>
    </Modal>
  );
};
