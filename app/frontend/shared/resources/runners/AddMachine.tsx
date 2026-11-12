import {
  Alert,
  Button,
  Checkbox,
  Code,
  CopyButton,
  Group,
  Modal,
  SegmentedControl,
  Stack,
  Text,
  TextInput,
} from '@mantine/core';
import { IconCheck, IconCopy, IconPlus } from '@tabler/icons-react';
import { useState } from 'react';

import type { Runner } from '@/types/generated';

import { apiRequest, notifyApiFailure } from 'shared/lib/apiFetch';
import { formatDateTime } from 'shared/lib/formatDate';

import { installScript, isValidMachineName, suggestMachineName, type MachineRegistration } from './machineInstructions';
import type { RunnerPaths } from './runnerConfig';

interface AddMachineProps {
  runner: Runner;
  paths: RunnerPaths;
}

/**
 * "Add machine" on a `manual` runner's page (DESIGN.md §6.3). Pressing the button mints a single-use
 * registration token (1 h) and shows it inside the install sequence. The server keeps only its digest,
 * so the token lives in this component's state alone: closing the dialog discards it, and the next
 * press mints another.
 */
export function AddMachine({ runner, paths }: AddMachineProps) {
  const [registration, setRegistration] = useState<MachineRegistration | null>(null);
  const [busy, setBusy] = useState(false);
  const [name, setName] = useState('');
  const [platform, setPlatform] = useState('');
  const [noAutoUpdate, setNoAutoUpdate] = useState(false);

  const open = async () => {
    setBusy(true);
    try {
      const issued = await apiRequest<MachineRegistration>(paths.registrationToken(runner.id), { method: 'POST' });
      setName(suggestMachineName(runner.name));
      setPlatform(issued.binaries[0]?.platform ?? '');
      setNoAutoUpdate(false);
      setRegistration(issued);
    } catch (error) {
      notifyApiFailure(error, 'The registration token was not created');
    } finally {
      setBusy(false);
    }
  };

  const binary = registration?.binaries.find((b) => b.platform === platform) ?? registration?.binaries[0];
  const validName = isValidMachineName(name);
  const script =
    registration && binary && validName ? installScript({ registration, binary, name, noAutoUpdate }) : null;

  return (
    <>
      <Button variant="default" leftSection={<IconPlus size={14} />} onClick={open} loading={busy}>
        Add machine
      </Button>

      <Modal
        opened={registration !== null}
        onClose={() => setRegistration(null)}
        title="Add machine"
        size="xl"
        centered
      >
        {registration && (
          <Stack gap="md">
            <Alert color="orange" variant="light">
              This token is shown once. It works for one machine, and only until{' '}
              {formatDateTime(registration.expiresAt)} (an hour from now). Close this window and press “Add machine”
              again for another.
            </Alert>

            <TextInput
              label="Machine name"
              description="How the machine is listed. Letters, digits, dots, dashes and underscores."
              value={name}
              onChange={(event) => setName(event.currentTarget.value)}
              error={
                validName ? undefined : 'Start with a letter or digit; then letters, digits, . _ - only (63 at most)'
              }
            />

            <Stack gap={4}>
              <Text fz="sm" fw={500}>
                Platform
              </Text>
              <SegmentedControl
                aria-label="Platform"
                value={binary?.platform ?? ''}
                onChange={setPlatform}
                data={registration.binaries.map((b) => ({ value: b.platform, label: b.platform }))}
              />
            </Stack>

            <Checkbox
              label="Turn off self-update (--no-auto-update)"
              description="By default the machine updates itself to the version this platform recommends when it is idle. Turn it off if you manage the binary yourself."
              checked={noAutoUpdate}
              onChange={(event) => setNoAutoUpdate(event.currentTarget.checked)}
            />

            <Code block aria-label="Install instructions" style={{ whiteSpace: 'pre-wrap', wordBreak: 'break-all' }}>
              {script ?? 'Enter a valid machine name to see the instructions.'}
            </Code>

            <Group justify="space-between">
              <Text fz="xs" c="dimmed">
                Run this on a Linux machine with systemd and Docker, as a user who can use sudo, with curl and sha256sum, that can reach {registration.gatewayUrl}. The SHA-256 is this
                platform’s own for aixle-runner {registration.version}.
              </Text>
              <CopyButton value={script ?? ''}>
                {({ copied, copy }) => (
                  <Button
                    variant="light"
                    onClick={copy}
                    disabled={script === null}
                    leftSection={copied ? <IconCheck size={14} /> : <IconCopy size={14} />}
                  >
                    {copied ? 'Copied' : 'Copy'}
                  </Button>
                )}
              </CopyButton>
            </Group>
          </Stack>
        )}
      </Modal>
    </>
  );
}
