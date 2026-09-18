import { router } from '@inertiajs/react';
import { Alert, Anchor, Button, Code, Group, Modal, PasswordInput, Radio, Stack, Text } from '@mantine/core';
import { IconAlertCircle, IconExternalLink } from '@tabler/icons-react';
import { useCallback, useEffect, useState } from 'react';

export interface GithubProps {
  /** False on a deployment with no GITHUB_APP_ID / GITHUB_APP_SLUG — typically a local one. */
  appConfigured: boolean;
}

interface Props {
  opened: boolean;
  onClose: () => void;
  basePath: string;
  github?: GithubProps;
}

type AuthMode = 'app' | 'pat';

// Pre-ticks `repo` on GitHub's token form and names the token, so the required
// scope is not something the reader has to translate from prose.
const PAT_CREATE_URL = 'https://github.com/settings/tokens/new?scopes=repo&description=Aixle%20Flow';

export const GithubConnectModal = ({ opened, onClose, basePath, github }: Props) => {
  const appConfigured = github?.appConfigured ?? true;

  // The App is the recommended path and the default — except where it cannot
  // work at all, when defaulting to it would mean opening on a button whose
  // only outcome is "GitHub App is not configured".
  const defaultMode: AuthMode = appConfigured ? 'app' : 'pat';
  const [authMode, setAuthMode] = useState<AuthMode>(defaultMode);
  const [pat, setPat] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (opened) setAuthMode(defaultMode);
  }, [opened, defaultMode]);

  const close = useCallback(() => {
    onClose();
    setPat('');
    setError(null);
  }, [onClose]);

  const installApp = useCallback(() => {
    // Server-side endpoint mints a SIGNED state (Oauth::State) and redirects to GitHub's
    // app-install URL — the state is never built or forgeable client-side (§7).
    window.location.href = `${basePath}/github_app_install`;
  }, [basePath]);

  // Only the token is posted, and only from this branch: `authMode` decides on
  // the server which credential is read, so a switch between modes can never
  // submit the other path's credential.
  const connectPat = useCallback(() => {
    const token = pat.trim();
    if (!token) return;

    setError(null);
    setLoading(true);
    router.post(
      basePath,
      { provider: 'github', authMode: 'pat', personalAccessToken: token },
      {
        preserveScroll: true,
        onSuccess: () => close(),
        onError: (errors) => {
          const message = typeof errors === 'object' && errors ? Object.values(errors).join(' ') : '';
          setError(message || 'Failed to connect GitHub');
        },
        onFinish: () => setLoading(false),
      },
    );
  }, [basePath, close, pat]);

  return (
    <Modal opened={opened} onClose={close} title="Connect GitHub" centered size="lg">
      <Stack gap="md">
        <Radio.Group value={authMode} onChange={(value) => setAuthMode(value as AuthMode)}>
          <Stack gap="sm">
            <Radio
              value="app"
              disabled={!appConfigured}
              label="I own the organization and can install the app (Recommended)"
              description={
                appConfigured
                  ? 'Aixle gets its own short-lived, repository-scoped token, org-wide repository access, and GitHub webhooks that close CI gates the moment a check finishes.'
                  : 'Unavailable on this deployment — no GitHub App is configured (GITHUB_APP_ID, GITHUB_APP_SLUG and a private key).'
              }
            />
            <Radio
              value="pat"
              label="I'm a developer and just want to try it (personal access token)"
              description="Paste a token instead of installing anything. Meant for trying Aixle out locally or on a personal project."
            />
          </Stack>
        </Radio.Group>

        {authMode === 'app' ? (
          <Text size="sm" c="dimmed">
            You will be sent to GitHub to choose the account and the repositories the app may reach, then returned here.
          </Text>
        ) : (
          <>
            <Alert color="orange" icon={<IconAlertCircle size={16} />} title="This acts as you, not as Aixle">
              <Text size="sm">
                A personal access token carries your own GitHub permissions, and every commit, push and pull request an
                agent makes is attributed to you. GitHub also delivers no webhooks to a token, so CI gates resolve by
                polling instead of the moment a check finishes — and not at all if this deployment cannot reach
                github.com. Use the app in production.
              </Text>
            </Alert>
            <PasswordInput
              label="Personal access token"
              description="Stored encrypted. It is never shown again — to change it, paste a new one."
              placeholder="ghp_... or github_pat_..."
              value={pat}
              onChange={(e) => setPat(e.currentTarget.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') connectPat();
              }}
              autoFocus
            />
            <Text size="sm" c="dimmed">
              Classic token: <Code>repo</Code> for private repositories, or <Code>public_repo</Code> for public ones
              only. Fine-grained token: <Code>Contents</Code> read (and write if agents should push) plus{' '}
              <Code>Metadata</Code> read, on the repositories you want to attach. GitHub tokens expire — when one does,
              connect again with a new token.
            </Text>
            <Anchor href={PAT_CREATE_URL} target="_blank" rel="noopener noreferrer" size="sm">
              <Group gap={4} component="span">
                Create a token on GitHub
                <IconExternalLink size={14} />
              </Group>
            </Anchor>
          </>
        )}

        {error && (
          <Alert color="red" icon={<IconAlertCircle size={16} />}>
            {error}
          </Alert>
        )}

        <Group justify="flex-end">
          <Button variant="default" onClick={close}>
            Cancel
          </Button>
          {authMode === 'app' ? (
            <Button onClick={installApp} disabled={!appConfigured}>
              Continue to GitHub
            </Button>
          ) : (
            <Button onClick={connectPat} loading={loading} disabled={!pat.trim()}>
              Connect
            </Button>
          )}
        </Group>
      </Stack>
    </Modal>
  );
};
