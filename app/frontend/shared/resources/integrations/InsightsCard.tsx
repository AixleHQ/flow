import { router } from '@inertiajs/react';
import { Alert, Badge, Button, Card, Group, Modal, Select, Stack, Switch, Text, TextInput } from '@mantine/core';
import { modals } from '@mantine/modals';
import { IconAlertTriangle } from '@tabler/icons-react';
import { useState } from 'react';

import { requestJson } from './requestJson';

export interface InsightsProps {
  enabled: boolean;
  connection?: { status: string; organizationName: string | null; connectedAt: string } | null;
  project?: { export: boolean; insightsProjectId: string | null };
  canConnect?: boolean;
  canManage?: boolean;
  delivery?: {
    pending: number;
    oldestPendingAt: string | null;
    failed: number;
    lastError: string | null;
  };
}

interface Props {
  insights: InsightsProps;
  projectId: number;
}

const MATCH_BY_REPOSITORY = '';

// The company's connection to Aixle Insights and this project's export switch and mapping
// (docs/design/insights-otlp-relay.md §3). The connection's secret never reaches the page.
export const InsightsCard = ({ insights, projectId }: Props) => {
  const base = `/company/projects/${projectId}/insights`;
  const [connectOpen, setConnectOpen] = useState(false);
  const [code, setCode] = useState('');
  const [codeError, setCodeError] = useState<string | null>(null);
  const [projects, setProjects] = useState<{ value: string; label: string }[] | null>(null);
  const [projectsError, setProjectsError] = useState<string | null>(null);

  if (!insights.enabled) return null;

  const { connection, project, delivery } = insights;
  const connected = connection != null;
  const broken = connection?.status === 'error';

  const closeConnect = () => {
    setConnectOpen(false);
    setCode('');
    setCodeError(null);
  };

  const connect = () => {
    setCodeError(null);
    router.post(
      `${base}/connect`,
      { code: code.trim() },
      { preserveScroll: true, onSuccess: closeConnect, onError: (errors) => setCodeError(errors.code ?? null) },
    );
  };

  const save = (changes: Record<string, boolean | string>) => router.patch(base, changes, { preserveScroll: true });

  const loadProjects = async () => {
    if (projects) return;
    try {
      const { projects: list } = (await requestJson(`${base}/projects`, {}, 'Could not load Insights projects')) as {
        projects: { id: string; name: string }[];
      };
      setProjects(list.map((p) => ({ value: p.id, label: p.name })));
    } catch (e) {
      setProjectsError(e instanceof Error ? e.message : 'Could not load Insights projects');
    }
  };

  const confirmDisconnect = () =>
    modals.openConfirmModal({
      title: 'Disconnect Aixle Insights',
      children: (
        <Text size="sm">
          Every project of the company stops sending telemetry to {connection?.organizationName ?? 'Insights'}. What was
          already sent stays there.
        </Text>
      ),
      labels: { confirm: 'Disconnect', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => router.delete(`${base}/disconnect`, { preserveScroll: true }),
    });

  const mapping = project?.insightsProjectId ?? MATCH_BY_REPOSITORY;
  const mappingOptions = [
    { value: MATCH_BY_REPOSITORY, label: 'Match by repository' },
    ...(projects ?? (mapping ? [{ value: mapping, label: mapping }] : [])),
  ];

  return (
    <Card withBorder padding="lg" mb="lg">
      <Stack gap="sm">
        <Group justify="space-between">
          <Group gap="xs">
            <Text fw={600}>Aixle Insights</Text>
            {connected && (
              <Badge color={broken ? 'red' : 'green'} variant="light">
                {broken ? 'Needs a new code' : 'Connected'}
              </Badge>
            )}
          </Group>
          {insights.canConnect && !connected && <Button onClick={() => setConnectOpen(true)}>Connect</Button>}
          {insights.canConnect && connected && (
            <Group gap="xs">
              {broken ? (
                <Button variant="light" onClick={() => setConnectOpen(true)}>
                  Enter a new code
                </Button>
              ) : (
                <Button variant="default" onClick={() => router.post(`${base}/rotate`, {}, { preserveScroll: true })}>
                  Rotate secret
                </Button>
              )}
              <Button variant="subtle" color="red" onClick={confirmDisconnect}>
                Disconnect
              </Button>
            </Group>
          )}
        </Group>

        {!connected && (
          <Text size="sm" c="dimmed">
            Send what the agents report to an Aixle Insights organization. An owner of the organization creates a
            one-time pairing code in Insights; a company admin enters it here.
          </Text>
        )}

        {connected && (
          <>
            <Text size="sm" c="dimmed">
              The company sends to {connection.organizationName ?? 'Insights'}. Each project is sent only once it is
              switched on.
            </Text>
            <Switch
              label="Send this project's agent telemetry to Insights"
              description="Everything the agents report, as they report it — model calls, tokens and cost, prompts, replies, tool calls with their arguments and output — with the person, project and session. Only the session's own secrets are masked: a token typed into a prompt or read from a file is sent as it is. Starts with new activity; never for client projects."
              checked={project?.export ?? false}
              disabled={!insights.canManage}
              onChange={(e) => save({ export: e.currentTarget.checked })}
            />
            {project?.export && (
              <Select
                label="Insights project"
                data={mappingOptions}
                value={mapping}
                disabled={!insights.canManage}
                onDropdownOpen={() => void loadProjects()}
                onChange={(value) => save({ insights_project_id: value ?? MATCH_BY_REPOSITORY })}
                error={projectsError}
                allowDeselect={false}
                maw={360}
              />
            )}
            {delivery && (delivery.pending > 0 || delivery.failed > 0) && (
              <Text size="xs" c="dimmed">
                Waiting to be sent: {delivery.pending}
                {delivery.oldestPendingAt && ` (oldest from ${new Date(delivery.oldestPendingAt).toLocaleString()})`} ·
                not accepted: {delivery.failed}
              </Text>
            )}
            {delivery?.lastError && (
              <Alert color="orange" icon={<IconAlertTriangle size={16} />} title="Last problem">
                {delivery.lastError}
              </Alert>
            )}
          </>
        )}
      </Stack>

      <Modal opened={connectOpen} onClose={closeConnect} title="Connect Aixle Insights">
        <Stack>
          <Text size="sm">
            Enter the pairing code an owner of the Insights organization created. It works once, for 15 minutes.
          </Text>
          <TextInput
            label="Pairing code"
            placeholder="XXXX-XXXX"
            value={code}
            onChange={(e) => setCode(e.currentTarget.value)}
            error={codeError}
            autoFocus
          />
          <Group justify="flex-end">
            <Button variant="default" onClick={closeConnect}>
              Cancel
            </Button>
            <Button onClick={connect} disabled={code.trim() === ''}>
              Connect
            </Button>
          </Group>
        </Stack>
      </Modal>
    </Card>
  );
};
