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
import { IconCheck, IconChevronDown, IconChevronRight, IconCopy, IconPlus } from '@tabler/icons-react';
import { useState, type ReactNode } from 'react';

import type { Runner } from '@/types/generated';

import { apiRequest, notifyApiFailure } from 'shared/lib/apiFetch';
import { formatDateTime } from 'shared/lib/formatDate';

import {
  DOCKER_NAME,
  dockerCommand,
  installCommand,
  installScript,
  isValidKeepDirectory,
  isValidMachineName,
  runnerImage,
  shellQuote,
  suggestMachineName,
  type DockerKeep,
  type MachineRegistration,
} from './machineInstructions';
import type { RunnerPaths } from './runnerConfig';

type Tab = 'docker' | 'service';

/** The Docker version rule (add-machine.md §3.2), in the one set of words used everywhere. */
const DOCKER_VERSION_RULE =
  'Needs Docker 26 or later. On older Docker, tick Keep it in a directory on this machine, or use the Linux service.';

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
  const [tab, setTab] = useState<Tab>('docker');
  const [privateRegistry, setPrivateRegistry] = useState(false);
  const [keepChoice, setKeepChoice] = useState<'none' | 'volume' | 'directory'>('none');
  const [directory, setDirectory] = useState(DEFAULT_DIRECTORY);
  const [noAutoUpdate, setNoAutoUpdate] = useState(false);
  const [platform, setPlatform] = useState('');

  const open = async () => {
    setBusy(true);
    try {
      const issued = await apiRequest<MachineRegistration>(paths.registrationToken(runner.id), { method: 'POST' });
      setName(suggestMachineName(runner.name));
      setTab('docker');
      setPrivateRegistry(false);
      setKeepChoice('none');
      setDirectory(DEFAULT_DIRECTORY);
      setNoAutoUpdate(false);
      setPlatform(issued.binaries[0]?.platform ?? '');
      setRegistration(issued);
    } catch (error) {
      notifyApiFailure(error, 'The registration token was not created');
    } finally {
      setBusy(false);
    }
  };

  const validName = isValidMachineName(name);
  const validDirectory = keepChoice !== 'directory' || isValidKeepDirectory(directory);
  const keep: DockerKeep = keepChoice === 'directory' ? { directory } : keepChoice;
  const binary = registration?.binaries.find((b) => b.platform === platform) ?? registration?.binaries[0];

  let command: string | null = null;
  if (registration && validName && validDirectory) {
    command =
      tab === 'docker'
        ? dockerCommand({ registration, name, privateRegistry, keep })
        : installCommand({ registration, name, noAutoUpdate });
  }

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

            <SegmentedControl
              aria-label="How to run the runner"
              value={tab}
              onChange={(value) => setTab(value as Tab)}
              data={[
                { value: 'docker', label: 'Docker' },
                { value: 'service', label: 'Linux service' },
              ]}
            />

            {tab === 'docker' ? (
              <Stack gap="xs">
                <Checkbox
                  label="Images from a private registry"
                  description="Mounts your Docker config file so the machine can pull agent images. A file with a credential helper (credsStore) does not work in the container."
                  checked={privateRegistry}
                  onChange={(event) => setPrivateRegistry(event.currentTarget.checked)}
                />
                <Checkbox
                  label="Keep the registration in a volume"
                  description="The machine stays registered when the container stops, and starts again without the token."
                  checked={keepChoice === 'volume'}
                  onChange={(event) => setKeepChoice(event.currentTarget.checked ? 'volume' : 'none')}
                />
                <Checkbox
                  label="Keep it in a directory on this machine (also works on Docker older than 26)"
                  checked={keepChoice === 'directory'}
                  onChange={(event) => setKeepChoice(event.currentTarget.checked ? 'directory' : 'none')}
                />
                {keepChoice === 'directory' && (
                  <TextInput
                    label="Directory on this machine"
                    description="An absolute path. Its files are the machine's registration: keep them private."
                    value={directory}
                    onChange={(event) => setDirectory(event.currentTarget.value)}
                    error={validDirectory ? undefined : 'Enter an absolute path, starting with /'}
                  />
                )}
              </Stack>
            ) : (
              <Checkbox
                label="Turn off self-update (--no-auto-update)"
                description="By default the machine updates itself to the version this platform recommends when it is idle. Turn it off if you manage the binary yourself."
                checked={noAutoUpdate}
                onChange={(event) => setNoAutoUpdate(event.currentTarget.checked)}
              />
            )}

            <Code block aria-label="Install instructions" style={{ whiteSpace: 'pre-wrap', wordBreak: 'break-all' }}>
              {command ?? 'Enter a valid machine name to see the instructions.'}
            </Code>

            <Group justify="space-between" align="flex-start" wrap="nowrap">
              <Stack gap={4}>
                {tab === 'docker' ? (
                  <>
                    <Text fz="xs" c="dimmed">
                      Run this on a machine with Docker that can reach {registration.gatewayUrl}. On Linux, if your user
                      is not in the docker group, put sudo in front. The image is aixle-runner {registration.version}.
                    </Text>
                    <Text fz="xs" c="dimmed">
                      {DOCKER_VERSION_RULE}
                    </Text>
                    <Text fz="xs" c="dimmed">
                      Without a keep box the command runs in the foreground, and stopping it (Ctrl+C or docker stop)
                      removes the machine. If the output says the token is refused, close this window and use a new
                      command. A runner in Docker does not update itself: to update it, run the image of the new
                      version. On an arm64 machine (Apple Silicon, ARM Linux) sessions run an agent image natively when
                      it is published for arm64, and the amd64 image under emulation otherwise.
                    </Text>
                  </>
                ) : (
                  <Text fz="xs" c="dimmed">
                    Run this on a Linux machine with systemd and Docker that can reach {registration.gatewayUrl}, as a
                    user who can use sudo, with curl and sha256sum. The script installs aixle-runner{' '}
                    {registration.version} after checking the SHA-256 this platform pins for it.
                  </Text>
                )}
              </Stack>
              <CopyButton value={command ?? ''}>
                {({ copied, copy }) => (
                  <Button
                    variant="light"
                    onClick={copy}
                    disabled={command === null}
                    leftSection={copied ? <IconCheck size={14} /> : <IconCopy size={14} />}
                  >
                    {copied ? 'Copied' : 'Copy'}
                  </Button>
                )}
              </CopyButton>
            </Group>

            <Section title="Remove this machine">
              <RemoveMachine
                tab={tab}
                keep={keepChoice}
                directory={directory}
                version={registration.version}
                validDirectory={validDirectory}
              />
            </Section>

            {tab === 'service' && (
              <Section title="Install step by step">
                <Text fz="xs" c="dimmed">
                  The same steps without the script, for when you would rather not pipe a script into a root shell.
                  Download the binary, compare its SHA-256 with the one this platform pins, then register and start it.
                </Text>
                <SegmentedControl
                  aria-label="Platform"
                  value={binary?.platform ?? ''}
                  onChange={setPlatform}
                  data={registration.binaries.map((b) => ({ value: b.platform, label: b.platform }))}
                />
                <Code
                  block
                  aria-label="Step-by-step instructions"
                  style={{ whiteSpace: 'pre-wrap', wordBreak: 'break-all' }}
                >
                  {binary && validName
                    ? installScript({ registration, binary, name, noAutoUpdate })
                    : 'Enter a valid machine name to see the instructions.'}
                </Code>
              </Section>
            )}
          </Stack>
        )}
      </Modal>
    </>
  );
}

const DEFAULT_DIRECTORY = '/var/lib/aixle-runner';

/** A collapsed section: its content is not in the page until it is opened. */
function Section({ title, children }: { title: string; children: ReactNode }) {
  const [opened, setOpened] = useState(false);
  return (
    <Stack gap="xs">
      <Button
        variant="subtle"
        size="compact-sm"
        justify="flex-start"
        aria-expanded={opened}
        leftSection={opened ? <IconChevronDown size={14} /> : <IconChevronRight size={14} />}
        onClick={() => setOpened((value) => !value)}
      >
        {title}
      </Button>
      {opened && <Stack gap="xs">{children}</Stack>}
    </Stack>
  );
}

interface RemoveMachineProps {
  tab: Tab;
  keep: 'none' | 'volume' | 'directory';
  directory: string;
  version: string;
  validDirectory: boolean;
}

/** How to take a machine away again (add-machine.md §2.3), for the command the dialog shows. */
function RemoveMachine({ tab, keep, directory, version, validDirectory }: RemoveMachineProps) {
  if (tab === 'service') {
    return (
      <>
        <Text fz="xs">
          Run these on the machine. The first removes it from the platform; you can also press Revoke or Delete on the
          runner’s page.
        </Text>
        <Code block aria-label="Remove instructions">
          {'sudo aixle-runner unregister\nsudo aixle-runner service uninstall'}
        </Code>
      </>
    );
  }
  if (keep === 'none') {
    return (
      <Text fz="xs">
        Stop the command: press Ctrl+C, or run <Code>docker stop {DOCKER_NAME}</Code> from another terminal. The runner
        removes its session containers and unregisters the machine. If it is killed instead (docker kill, a power
        loss), the machine shows as not answering: press Revoke or Delete on the runner’s page, and see the user guide
        for the containers it leaves.
      </Text>
    );
  }
  const image = shellQuote(runnerImage(version));
  const lines = [
    '# 1. On the runner’s page, press Revoke or Delete for this machine',
    '# 2. Remove the container',
    `docker rm -f ${DOCKER_NAME}`,
    ...(keep === 'volume'
      ? [`docker volume rm ${DOCKER_NAME}`]
      : validDirectory
        ? [`sudo rm -rf ${shellQuote(directory)}`]
        : []),
    '',
    '# Or remove the machine from the machine’s side instead of step 1:',
    `# docker stop ${DOCKER_NAME} && docker run --rm --volumes-from ${DOCKER_NAME} ${image} unregister`,
  ];
  return (
    <>
      <Text fz="xs">
        The registration is kept, so stopping the container does not remove the machine. Removing the volume or the
        directory deletes the machine’s credentials: Revoke the machine and add it again to use it.
      </Text>
      <Code block aria-label="Remove instructions" style={{ whiteSpace: 'pre-wrap' }}>
        {lines.join('\n')}
      </Code>
    </>
  );
}
