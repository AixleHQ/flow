import { router } from '@inertiajs/react';
import { Alert, Button, Group, Modal, Select, Stack, Switch, Text, TextInput } from '@mantine/core';
import { IconAlertTriangle } from '@tabler/icons-react';
import { useCallback, useEffect, useState } from 'react';

import { insightsPath, type InsightsProps } from './insightsActions';
import { requestJson } from './requestJson';

export type { InsightsProps } from './insightsActions';

const MATCH_BY_REPOSITORY = '';

interface ConnectProps {
  opened: boolean;
  onClose: () => void;
  projectId: number;
}

// The company's connection to Aixle Insights (docs/design/insights-otlp-relay.md §3): an owner
// of the organization creates a one-time code in Insights, a company admin enters it here.
export const InsightsConnectModal = ({ opened, onClose, projectId }: ConnectProps) => {
  const [code, setCode] = useState('');
  const [error, setError] = useState<string | null>(null);

  const close = () => {
    setCode('');
    setError(null);
    onClose();
  };

  const connect = () => {
    setError(null);
    router.post(
      `${insightsPath(projectId)}/connect`,
      { code: code.trim() },
      { preserveScroll: true, onSuccess: close, onError: (errors) => setError(errors.code ?? null) },
    );
  };

  return (
    <Modal opened={opened} onClose={close} title="Connect Aixle Insights">
      <Stack>
        <Text size="sm">
          Enter the pairing code an owner of the Insights organization created. It works once, for 15 minutes.
        </Text>
        <TextInput
          label="Pairing code"
          placeholder="XXXX-XXXX"
          value={code}
          onChange={(e) => setCode(e.currentTarget.value)}
          error={error}
          autoFocus
        />
        <Group justify="flex-end">
          <Button variant="default" onClick={close}>
            Cancel
          </Button>
          <Button onClick={connect} disabled={code.trim() === ''}>
            Connect
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
};

interface ProjectProps {
  opened: boolean;
  onClose: () => void;
  projectId: number;
  insights: InsightsProps;
}

// This project's part of the connection: whether its agents' telemetry goes to Insights,
// which Insights project it lands in, and what is still on its way.
export const InsightsProjectModal = ({ opened, onClose, projectId, insights }: ProjectProps) => {
  const base = insightsPath(projectId);
  const [projects, setProjects] = useState<{ value: string; label: string }[] | null>(null);
  const [projectsError, setProjectsError] = useState<string | null>(null);
  const { project, delivery } = insights;

  const loadProjects = useCallback(async () => {
    if (projects) return;
    try {
      const { projects: list } = (await requestJson(`${base}/projects`, {}, 'Could not load Insights projects')) as {
        projects: { id: string; name: string }[];
      };
      setProjects(list.map((p) => ({ value: p.id, label: p.name })));
    } catch (e) {
      setProjectsError(e instanceof Error ? e.message : 'Could not load Insights projects');
    }
  }, [base, projects]);

  // Only Insights knows a mapped project's name, so its list is loaded as soon as one is shown.
  const mapping = project?.insightsProjectId ?? MATCH_BY_REPOSITORY;
  useEffect(() => {
    if (opened && project?.export && mapping) void loadProjects();
  }, [opened, project?.export, mapping, loadProjects]);

  const save = (changes: Record<string, boolean | string>) => router.patch(base, changes, { preserveScroll: true });
  const mappingOptions = [
    { value: MATCH_BY_REPOSITORY, label: 'Match by repository' },
    ...(projects ?? (mapping ? [{ value: mapping, label: projectsError ? mapping : 'Loading…' }] : [])),
  ];

  return (
    <Modal opened={opened} onClose={onClose} title="Aixle Insights for this project" size="lg">
      <Stack>
        <Text size="sm" c="dimmed">
          The company sends to {insights.connection?.organizationName ?? 'Insights'}. Each project is sent only once it
          is switched on.
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
            description="Where this project's activity lands in Insights. By default Insights matches it by repository."
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
            {delivery.oldestPendingAt && ` (oldest from ${new Date(delivery.oldestPendingAt).toLocaleString()})`} · not
            accepted: {delivery.failed}
          </Text>
        )}
        {delivery?.lastError && (
          <Alert color="orange" icon={<IconAlertTriangle size={16} />} title="Last problem">
            {delivery.lastError}
          </Alert>
        )}
        <Group justify="flex-end">
          <Button variant="default" onClick={onClose}>
            Close
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
};
