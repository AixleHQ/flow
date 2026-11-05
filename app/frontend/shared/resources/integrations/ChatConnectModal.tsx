import { Button, Group, Modal, Radio, Stack, Text } from '@mantine/core';
import { useEffect, useState } from 'react';

export type ChatProvider = 'slack' | 'teams';
export type ChatScope = 'company' | 'project';

interface Props {
  /** The messenger being connected; null keeps the dialog closed. */
  provider: ChatProvider | null;
  /** A company admin may connect for every project; anyone else for this one. */
  canManageCompany: boolean;
  onClose: () => void;
  onConnect: (provider: ChatProvider, scope: ChatScope) => void;
}

const LABELS: Record<ChatProvider, string> = { slack: 'Slack', teams: 'Microsoft Teams' };

const NEXT_STEP: Record<ChatProvider, string> = {
  slack: 'Next, Slack asks you to pick a workspace and approve the app.',
  teams: 'Next, you get a link for an administrator of your Microsoft 365 organization to approve.',
};

export const ChatConnectModal = ({ provider, canManageCompany, onClose, onConnect }: Props) => {
  const defaultScope: ChatScope = canManageCompany ? 'company' : 'project';
  const [scope, setScope] = useState<ChatScope>(defaultScope);

  useEffect(() => {
    if (provider) setScope(defaultScope);
  }, [provider, defaultScope]);

  const label = provider ? LABELS[provider] : '';

  return (
    <Modal opened={!!provider} onClose={onClose} title={`Connect ${label}`} centered size="md">
      <Stack gap="md">
        <Radio.Group label="Who can use it" value={scope} onChange={(value) => setScope(value as ChatScope)}>
          <Stack gap="sm" mt="xs">
            <Radio
              value="company"
              label="Every project in the company"
              description={
                canManageCompany
                  ? 'Any project can connect its channels and start workflows from them.'
                  : 'Only a company admin can connect it for the whole company.'
              }
              disabled={!canManageCompany}
            />
            <Radio
              value="project"
              label="Only this project"
              description="Other projects in the company don't see it. A company admin can share it with every project later."
            />
          </Stack>
        </Radio.Group>
        {provider && (
          <Text size="sm" c="dimmed">
            {NEXT_STEP[provider]}
          </Text>
        )}
        <Group justify="flex-end">
          <Button variant="default" onClick={onClose}>
            Cancel
          </Button>
          <Button onClick={() => provider && onConnect(provider, scope)}>Continue</Button>
        </Group>
      </Stack>
    </Modal>
  );
};
