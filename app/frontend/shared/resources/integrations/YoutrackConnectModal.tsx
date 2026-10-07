import { Alert, Anchor, Button, Group, Modal, Stack, Text, TextInput } from '@mantine/core';
import { IconAlertCircle } from '@tabler/icons-react';
import { useCallback, useState } from 'react';

import { useConfirmClose } from 'shared/lib/hooks/useConfirmClose';

import { requestJson } from './requestJson';

export interface YoutrackProps {
  enabled: boolean;
  marketplaceUrl: string;
}

const DOCS_URL = '/docs/youtrack';

interface ConnectProps {
  opened: boolean;
  onClose: () => void;
  basePath: string;
  youtrack: YoutrackProps;
}

export const YoutrackConnectModal = ({ opened, onClose, basePath, youtrack }: ConnectProps) => {
  const [instanceUrl, setInstanceUrl] = useState('');
  const [redirecting, setRedirecting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const close = useCallback(() => {
    onClose();
    setInstanceUrl('');
    setError(null);
  }, [onClose]);
  const requestClose = useConfirmClose(instanceUrl !== '', close);

  const proceed = async () => {
    setError(null);
    setRedirecting(true);
    try {
      const { redirect_url: redirectUrl } = (await requestJson(
        `${basePath}/youtrack_connect`,
        { method: 'POST', body: JSON.stringify({ instance_url: instanceUrl.trim() }) },
        'Could not start connecting YouTrack',
      )) as { redirect_url: string };
      window.location.assign(redirectUrl);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not start connecting YouTrack');
      setRedirecting(false);
    }
  };

  return (
    <Modal opened={opened} onClose={requestClose} title="Connect YouTrack" size="lg">
      <Stack gap="md">
        <Text size="sm" c="dimmed">
          YouTrack connects through the <b>Aixle Flow</b> app. A YouTrack administrator installs it once from{' '}
          <Anchor href={youtrack.marketplaceUrl} target="_blank" rel="noopener noreferrer">
            JetBrains Marketplace
          </Anchor>
          , then confirms the connection inside YouTrack. It needs YouTrack 2026.2 or later. See the{' '}
          <Anchor href={DOCS_URL}>YouTrack guide</Anchor>.
        </Text>
        <TextInput
          label="YouTrack URL"
          description="A self-hosted server's URL includes its path, such as https://tracker.example.com/youtrack."
          placeholder="https://acme.youtrack.cloud"
          value={instanceUrl}
          onChange={(e) => setInstanceUrl(e.currentTarget.value)}
        />
        {error && (
          <Alert color="red" icon={<IconAlertCircle size={16} />}>
            {error}
          </Alert>
        )}
        <Group justify="flex-end">
          <Button variant="default" onClick={requestClose}>
            Cancel
          </Button>
          <Button onClick={proceed} loading={redirecting} disabled={!instanceUrl.trim()}>
            Continue in YouTrack
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
};
