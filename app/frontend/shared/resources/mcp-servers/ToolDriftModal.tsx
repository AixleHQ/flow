import { router } from '@inertiajs/react';
import { Alert, Button, Code, Group, List, Modal, Stack, Text } from '@mantine/core';
import { IconAlertTriangle } from '@tabler/icons-react';
import { useState, type FC } from 'react';

import type { McpServer } from './types';

interface ToolDriftModalProps {
  server: McpServer | null;
  basePath: string;
  onClose: () => void;
}

const Section: FC<{ title: string; names: string[]; hint: string }> = ({ title, names, hint }) => {
  if (names.length === 0) return null;

  return (
    <Stack gap={4}>
      <Text fz={13} fw={600} c="var(--app-text-primary)">
        {title}
      </Text>
      <Text fz={12} c="dimmed">
        {hint}
      </Text>
      <List size="sm" spacing={2}>
        {names.map((name) => (
          <List.Item key={name}>
            <Code>{name}</Code>
          </List.Item>
        ))}
      </List>
    </Stack>
  );
};

// A modal earns its interruption here: accepting a tool change is a security
// decision, and it should not be a stray click inside a table row.
export const ToolDriftModal: FC<ToolDriftModalProps> = ({ server, basePath, onClose }) => {
  const [submitting, setSubmitting] = useState(false);
  const drift = server?.toolDrift;

  const accept = () => {
    if (!server) return;
    setSubmitting(true);
    router.post(
      `${basePath}/${server.id}/accept_tool_drift`,
      {},
      { onFinish: () => setSubmitting(false), onSuccess: onClose },
    );
  };

  return (
    <Modal opened={!!server} onClose={onClose} title={`Tool changes — ${server?.name ?? ''}`} size="lg">
      {server && drift && (
        <Stack gap="md">
          <Alert color="red" icon={<IconAlertTriangle size={16} />}>
            This server declares different tools than it did when you installed it. A tool description is text the agent
            reads and follows, so a change here can redirect what the agent does.
          </Alert>

          <Section
            title="Changed"
            names={drift.changed ?? []}
            hint="Same name, different description or input schema — review these first."
          />
          <Section title="Added" names={drift.added ?? []} hint="Capabilities that were not present at install." />
          <Section title="Removed" names={drift.removed ?? []} hint="Anything relying on these will stop working." />

          {drift.detected_at && (
            <Text fz={12} c="dimmed">
              Detected {new Date(drift.detected_at).toLocaleString()}
            </Text>
          )}

          <Group justify="flex-end" mt="sm">
            <Button variant="default" onClick={onClose}>
              Leave for now
            </Button>
            <Button color="red" variant="light" loading={submitting} onClick={accept}>
              Accept these changes
            </Button>
          </Group>
        </Stack>
      )}
    </Modal>
  );
};
