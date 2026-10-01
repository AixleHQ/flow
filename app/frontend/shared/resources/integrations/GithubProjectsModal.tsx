import { router } from '@inertiajs/react';
import { Alert, Anchor, Button, Group, Loader, Modal, MultiSelect, Stack, Text } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconAlertCircle } from '@tabler/icons-react';
import { useCallback, useEffect, useState } from 'react';

import type { Integration } from '@/types/generated';

import { useConfirmClose } from 'shared/lib/hooks/useConfirmClose';

import { requestJson } from './requestJson';

interface GithubProject {
  id: string;
  number: number;
  title: string;
  url: string;
}

interface Props {
  integration: Integration | null;
  onClose: () => void;
  basePath: string;
}

// Which of the organization's projects the connection puts on the Trackers page.
export const GithubProjectsModal = ({ integration, onClose, basePath }: Props) => {
  const [projects, setProjects] = useState<GithubProject[] | null>(null);
  const [projectIds, setProjectIds] = useState<string[]>([]);
  const [selected, setSelected] = useState<string[]>([]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!integration) return;
    let cancelled = false;
    setProjects(null);
    setError(null);
    setProjectIds(integration.githubProjects.map((p) => p.id));
    setSelected(integration.githubProjects.map((p) => p.id));
    requestJson(`${basePath}/${integration.id}/github_projects`, { method: 'GET' }, 'GitHub rejected the request')
      .then((result) => {
        if (cancelled) return;
        setProjects(result.projects as GithubProject[]);
        setProjectIds(result.selected as string[]);
        setSelected(result.selected as string[]);
      })
      .catch((e) => !cancelled && setError(e instanceof Error ? e.message : 'Could not list the GitHub projects'));
    return () => {
      cancelled = true;
    };
  }, [basePath, integration]);

  const dirty = projectIds.length !== selected.length || projectIds.some((id) => !selected.includes(id));
  const requestClose = useConfirmClose(dirty, onClose);

  const save = useCallback(() => {
    if (!integration) return;
    setSaving(true);
    router.patch(
      `${basePath}/${integration.id}`,
      { githubProjectIds: projectIds },
      {
        preserveScroll: true,
        onSuccess: onClose,
        onError: () => notifications.show({ message: 'Failed to save the GitHub projects', color: 'red' }),
        onFinish: () => setSaving(false),
      },
    );
  }, [basePath, integration, onClose, projectIds]);

  return (
    <Modal opened={!!integration} onClose={requestClose} title="GitHub Projects" size="lg">
      <Stack gap="md">
        <Text size="sm" c="dimmed">
          Each project you pick becomes a tracker: its Status field is the board&apos;s columns, and its issues and pull
          requests are the tracker&apos;s issues.
        </Text>
        {integration?.githubProjectsPermitted === false && (
          <Alert color="yellow" icon={<IconAlertCircle size={16} />}>
            The GitHub App has not been granted the Projects and Issues permissions on this organization yet. An
            organization owner approves them in the{' '}
            {integration.githubUrl ? (
              <Anchor href={integration.githubUrl} target="_blank" size="sm">
                installation settings
              </Anchor>
            ) : (
              'installation settings'
            )}
            .
          </Alert>
        )}
        {error && (
          <Alert color="red" icon={<IconAlertCircle size={16} />}>
            {error}
          </Alert>
        )}
        {projects === null && !error && <Loader size="sm" aria-label="Loading projects" />}
        {projects && (
          <MultiSelect
            label="GitHub projects"
            description="A project you remove is detached."
            data={projects.map((p) => ({ value: p.id, label: `${p.title} (#${p.number})` }))}
            value={projectIds}
            onChange={setProjectIds}
            searchable
          />
        )}
        <Group justify="flex-end">
          <Button variant="default" onClick={requestClose}>
            Cancel
          </Button>
          <Button onClick={save} loading={saving} disabled={!projects}>
            Save
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
};
