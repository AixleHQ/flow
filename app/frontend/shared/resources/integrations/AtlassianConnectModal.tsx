import { Badge, Group, Modal, Stack, Text, UnstyledButton } from '@mantine/core';
import { IconChevronRight } from '@tabler/icons-react';

import { IntegrationLogo } from 'shared/ui/IntegrationLogo';

interface Product {
  available: boolean;
  connected: boolean;
  onChoose: () => void;
}

interface Props {
  opened: boolean;
  onClose: () => void;
  jira: Product;
  bitbucket: Product;
}

const PRODUCTS = [
  { key: 'jira', name: 'Jira', detail: 'Issues as trackers: tracker triggers and the tracker_* tools' },
  { key: 'bitbucket', name: 'Bitbucket', detail: 'Repositories, pull requests and CI gates' },
] as const;

// One entry point for the Atlassian products this project can connect. Each
// card opens that product's own connect flow; the page brings the chooser back
// when the flow closes, so both can be connected in one sitting.
export const AtlassianConnectModal = ({ opened, onClose, jira, bitbucket }: Props) => {
  const products = { jira, bitbucket };

  return (
    <Modal opened={opened} onClose={onClose} title="Connect Atlassian" centered size="md">
      <Stack gap="sm">
        <Text size="sm" c="dimmed">
          Jira and Bitbucket connect separately — each with its own credential — and can both serve this project.
        </Text>
        {PRODUCTS.filter(({ key }) => products[key].available).map(({ key, name, detail }) => (
          <UnstyledButton
            key={key}
            onClick={products[key].onChoose}
            aria-label={`Connect ${name}`}
            p="md"
            style={{ border: '1px solid var(--app-border-default)', borderRadius: 'var(--mantine-radius-md)' }}
          >
            <Group justify="space-between" wrap="nowrap">
              <Group gap="sm" wrap="nowrap">
                <IntegrationLogo provider={key} size={24} />
                <Stack gap={2}>
                  <Group gap="xs">
                    <Text fw={600}>{name}</Text>
                    {products[key].connected && (
                      <Badge size="xs" variant="light" color="green">
                        Connected
                      </Badge>
                    )}
                  </Group>
                  <Text size="sm" c="dimmed">
                    {detail}
                  </Text>
                  {products[key].connected && (
                    <Text size="xs" c="dimmed">
                      {`This project already has a ${name} connection — connecting again adds another.`}
                    </Text>
                  )}
                </Stack>
              </Group>
              <IconChevronRight size={16} />
            </Group>
          </UnstyledButton>
        ))}
      </Stack>
    </Modal>
  );
};
