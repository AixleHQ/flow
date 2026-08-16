import { Alert, List, Text } from '@mantine/core';
import { IconAlertTriangle } from '@tabler/icons-react';

/**
 * Shown wherever a `secret` config item is attached to a session, workflow or step.
 *
 * Attaching a secret is safe in the sense that its value is fetched on demand and
 * audited, and is scrubbed from the logs we store. It is NOT invisible: the value
 * reaches the model's context, and anything the agent prints is on the pod's stdout
 * before we can touch it. Saying so here is the honest half of the feature — see
 * docs/implementation-artifacts/spec-session-config-item-access.md.
 */
export const SecretExposureNotice = () => (
  <Alert variant="light" color="yellow" icon={<IconAlertTriangle size={16} />} title="What attaching a secret means">
    <Text size="sm">Any agent running here can read the value of the selected secrets. Every read is recorded.</Text>
    <List size="sm" spacing={4} mt="xs">
      <List.Item>Stored session logs have the value replaced with a fingerprint.</List.Item>
      <List.Item>
        It is still visible in the live terminal to anyone who can watch this session, and on the container&apos;s
        standard output, which our log stack collects unredacted.
      </List.Item>
    </List>
  </Alert>
);
