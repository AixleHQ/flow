import { Link, router } from '@inertiajs/react';
import {
  Alert,
  Anchor,
  Badge,
  Button,
  Code,
  Group,
  List,
  Modal,
  Paper,
  SimpleGrid,
  Stack,
  Table,
  Text,
  Title,
} from '@mantine/core';
import { IconAlertTriangle, IconArrowLeft } from '@tabler/icons-react';
import { useState, type ReactNode } from 'react';

import type { Runner } from '@/types/generated';

import { formatDateTime } from 'shared/lib/formatDate';
import { builderCompanyProjectWorkflowPath } from 'shared/routes';
import { PageHeader } from 'shared/ui/PageHeader';
import { StatusBadge } from 'shared/ui/StatusBadge';

import { accessWideners, humanize, setKeys, type RunnerPaths, type RunnerTypeOption } from './runnerConfig';
import { DEFAULT_REUSE_POLICY, lastSeen, REUSE_POLICY_COPY, runnerTypeTitle } from './runnerCopy';
import { RunnerFormModal } from './RunnerFormModal';

/** A workflow that names the runner, among those the page's viewer can open. */
export interface RunnerWorkflowUse {
  id: number;
  name: string;
  projectId: number;
  projectName: string;
}

interface RunnerDetailsProps {
  runner: Runner;
  runnerTypes: RunnerTypeOption[];
  canManage: boolean;
  paths: RunnerPaths;
  /** Where "back" goes, and what it is called. */
  backLabel: string;
  workflowsUsing?: RunnerWorkflowUse[];
}

const HEALTH_STATES: Runner['status'][] = ['pending', 'connected', 'degraded', 'unreachable'];

type Confirming = 'revoke' | 'delete' | null;

const formatValue = (value: unknown): string => (typeof value === 'string' ? value : JSON.stringify(value));

function Fact({ label, children }: { label: string; children: ReactNode }) {
  return (
    <Stack gap={2}>
      <Text fz={12} fw={600} c="dimmed" tt="uppercase" style={{ letterSpacing: 0.5 }}>
        {label}
      </Text>
      <Text component="div" fz="sm">
        {children}
      </Text>
    </Stack>
  );
}

function WorkflowList({ workflows }: { workflows: RunnerWorkflowUse[] }) {
  return (
    <List size="sm" spacing={2}>
      {workflows.map((workflow) => (
        <List.Item key={workflow.id}>
          <Anchor component={Link} href={builderCompanyProjectWorkflowPath(workflow.projectId, workflow.id)} fz="sm">
            {workflow.name}
          </Anchor>{' '}
          <Text span fz="xs" c="dimmed">
            {workflow.projectName}
          </Text>
        </List.Item>
      ))}
    </List>
  );
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <Paper withBorder radius="md" p="lg">
      <Title order={2} fz="md" fw={600} mb="md">
        {title}
      </Title>
      {children}
    </Paper>
  );
}

export function RunnerDetails({
  runner,
  runnerTypes,
  canManage,
  paths,
  backLabel,
  workflowsUsing = [],
}: RunnerDetailsProps) {
  const [editing, setEditing] = useState(false);
  const [confirming, setConfirming] = useState<Confirming>(null);
  const [busy, setBusy] = useState(false);

  const option = runnerTypes.find((t) => t.runnerType === runner.runnerType);
  const keys = setKeys(runner.config, option?.configSchema ?? {});
  const wideners = accessWideners(runner.config);
  const reuseCopy = REUSE_POLICY_COPY[runner.runnerType]?.[runner.reusePolicy];

  const lifecycle = (path: string) => {
    setBusy(true);
    router.post(path, {}, { preserveScroll: true, onFinish: () => setBusy(false) });
  };

  const confirm = () => {
    setBusy(true);
    const options = {
      preserveScroll: true,
      onFinish: () => {
        setBusy(false);
        setConfirming(null);
      },
    };
    if (confirming === 'delete') router.delete(paths.runner(runner.id), options);
    else router.post(paths.revoke(runner.id), {}, options);
  };

  const actions = canManage && (
    <Group gap="xs">
      {/* Revoke is final (RunnerStateMachine), so a revoked runner has nothing left to edit. */}
      {option && runner.status !== 'revoked' && (
        <Button variant="default" onClick={() => setEditing(true)}>
          Edit
        </Button>
      )}
      {HEALTH_STATES.includes(runner.status) && (
        <Button variant="default" onClick={() => lifecycle(paths.disable(runner.id))} disabled={busy}>
          Disable
        </Button>
      )}
      {runner.status === 'disabled' && (
        <Button variant="default" onClick={() => lifecycle(paths.enable(runner.id))} disabled={busy}>
          Enable
        </Button>
      )}
      {runner.status !== 'revoked' && (
        <Button variant="default" color="red" onClick={() => setConfirming('revoke')} disabled={busy}>
          Revoke
        </Button>
      )}
      <Button color="red" variant="light" onClick={() => setConfirming('delete')} disabled={busy}>
        Delete
      </Button>
    </Group>
  );

  return (
    <Stack gap="lg">
      <Anchor component={Link} href={paths.list} fz="sm">
        <Group gap={4} component="span">
          <IconArrowLeft size={14} />
          {backLabel}
        </Group>
      </Anchor>

      <PageHeader
        title={runner.name}
        meta={
          <>
            <Badge variant="default">{runnerTypeTitle(runner.runnerType)}</Badge>
            <StatusBadge state={runner.status} />
          </>
        }
        subtitle={runner.statusReason ?? undefined}
        actions={actions}
        mb={0}
      />

      <Section title="Overview">
        <SimpleGrid cols={{ base: 1, sm: 3 }} spacing="lg">
          <Fact label="Type">{runnerTypeTitle(runner.runnerType)}</Fact>
          <Fact label="Status">
            {humanize(runner.status)}
            {runner.statusReason ? `: ${runner.statusReason}` : ''}
          </Fact>
          <Fact label="Scope">{runner.scope === 'company' ? 'Company' : 'This project'}</Fact>
          <Fact label="Created by">{runner.createdByName ?? 'Deleted user'}</Fact>
          <Fact label="Created">{formatDateTime(runner.createdAt)}</Fact>
          <Fact label="Last seen">{lastSeen(runner)}</Fact>
        </SimpleGrid>
      </Section>

      <Section title="Limits">
        <SimpleGrid cols={{ base: 1, sm: 3 }} spacing="lg">
          <Fact label="Max concurrency">{runner.maxConcurrency}</Fact>
          <Fact label="Max environments">
            {runner.maxEnvironments ??
              (option?.capabilities.provisionable ? 'Same as max concurrency' : 'One per machine')}
          </Fact>
          <Fact label="Reuse policy">
            {humanize(runner.reusePolicy)}
            {runner.reusePolicy === DEFAULT_REUSE_POLICY[runner.runnerType] ? ' (default)' : ''}
            {reuseCopy && (
              <Text fz="xs" c="dimmed" mt={2}>
                {reuseCopy}
              </Text>
            )}
          </Fact>
        </SimpleGrid>
      </Section>

      <Section title="Capabilities">
        <Group gap="xs">
          {Object.entries(runner.capabilities).map(([name, enabled]) => (
            <Badge key={name} variant="default" color={enabled ? 'green' : 'gray'}>
              {humanize(name)}: {enabled ? 'yes' : 'no'}
            </Badge>
          ))}
        </Group>
      </Section>

      <Section title="Configuration">
        <Stack gap="md">
          {wideners.length > 0 && (
            <Alert
              color="orange"
              variant="light"
              icon={<IconAlertTriangle size={16} />}
              title="These options widen what the agent can touch on the machine"
            >
              <List size="sm" spacing={2}>
                {wideners.map((item) => (
                  <List.Item key={item}>{item}</List.Item>
                ))}
              </List>
            </Alert>
          )}
          {keys.length === 0 ? (
            <Text fz="sm" c="dimmed">
              Nothing set: every setting uses its default.
            </Text>
          ) : (
            <>
              <Table withTableBorder verticalSpacing="xs">
                <Table.Thead>
                  <Table.Tr>
                    <Table.Th>Setting</Table.Th>
                    <Table.Th>Value</Table.Th>
                  </Table.Tr>
                </Table.Thead>
                <Table.Tbody>
                  {keys.map(([key, value]) => (
                    <Table.Tr key={key}>
                      <Table.Td>
                        <Code>{key}</Code>
                      </Table.Td>
                      <Table.Td>
                        <Code style={{ whiteSpace: 'pre-wrap', wordBreak: 'break-all' }}>{formatValue(value)}</Code>
                      </Table.Td>
                    </Table.Tr>
                  ))}
                </Table.Tbody>
              </Table>
              <Text fz="sm" c="dimmed">
                Everything else uses its default.
              </Text>
            </>
          )}
        </Stack>
      </Section>

      <Section title="Workflows using it">
        {workflowsUsing.length === 0 ? (
          <Text fz="sm" c="dimmed">
            No workflow names this runner.
          </Text>
        ) : (
          <WorkflowList workflows={workflowsUsing} />
        )}
      </Section>

      {canManage && option && runner.status !== 'revoked' && (
        <RunnerFormModal
          opened={editing}
          onClose={() => setEditing(false)}
          runnerTypes={runnerTypes}
          paths={paths}
          runner={runner}
        />
      )}

      <Modal
        opened={confirming !== null}
        onClose={() => setConfirming(null)}
        title={confirming === 'delete' ? 'Delete runner' : 'Revoke runner'}
        size="sm"
        centered
      >
        <Text fz="sm" c="dimmed" mb="md">
          {confirming === 'delete'
            ? `${runner.name} is revoked and removed from the list. Workflows and past sessions keep its name.`
            : `${runner.name} stops accepting sessions for good. A revoked runner cannot be enabled again.`}
        </Text>
        {confirming === 'delete' && workflowsUsing.length > 0 && (
          <Alert color="yellow" variant="light" mb="md" title="Workflows still use this runner">
            <Text fz="sm" mb="xs">
              Their runs fail until each one picks another runner:
            </Text>
            <WorkflowList workflows={workflowsUsing} />
          </Alert>
        )}
        <Group justify="flex-end">
          <Button variant="default" onClick={() => setConfirming(null)} disabled={busy}>
            Cancel
          </Button>
          <Button color="red" onClick={confirm} loading={busy}>
            {confirming === 'delete' ? 'Delete' : 'Revoke'}
          </Button>
        </Group>
      </Modal>
    </Stack>
  );
}
