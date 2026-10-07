import { ActionIcon, Alert, Button, CopyButton, Group, Modal, Stack, Text, TextInput, Tooltip } from '@mantine/core';
import { IconCheck, IconCopy } from '@tabler/icons-react';

interface Props {
  /** The approval link, shown once right after the connection is requested. */
  url: string | null;
  onClose: () => void;
}

/**
 * The link a Microsoft 365 administrator opens to approve connecting their
 * organization. Only its digest is kept on the server, so this is the one time
 * it can be copied.
 */
export const TeamsApprovalModal = ({ url, onClose }: Props) => (
  <Modal opened={!!url} onClose={onClose} title="Connect Microsoft Teams" centered size="md">
    <Stack gap="md">
      <Text size="sm">
        Send this link to an administrator of your Microsoft 365 organization. They sign in with Microsoft to approve
        the connection, can grant access to files shared in Teams, and download the Teams app to publish for your
        organization. They do not need an Aixle account.
      </Text>
      <Group gap="xs" wrap="nowrap">
        <TextInput value={url ?? ''} readOnly style={{ flex: 1 }} aria-label="Approval link" />
        <CopyButton value={url ?? ''}>
          {({ copied, copy }) => (
            <Tooltip label={copied ? 'Copied' : 'Copy link'}>
              <ActionIcon variant="default" size="lg" onClick={copy} aria-label="Copy approval link">
                {copied ? <IconCheck size={16} /> : <IconCopy size={16} />}
              </ActionIcon>
            </Tooltip>
          )}
        </CopyButton>
      </Group>
      <Alert color="gray" variant="light">
        The link works for 7 days and is shown only now. If it is lost, request a new one from this page.
      </Alert>
      <Group justify="flex-end">
        <Button onClick={onClose}>Done</Button>
      </Group>
    </Stack>
  </Modal>
);
