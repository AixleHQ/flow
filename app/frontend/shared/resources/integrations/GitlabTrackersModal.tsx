import { router } from '@inertiajs/react';
import { Alert, Button, Group, Loader, Modal, MultiSelect, Select, Stack, Text } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconAlertCircle } from '@tabler/icons-react';
import { useCallback, useEffect, useState } from 'react';

import type { Integration } from '@/types/generated';

import { useConfirmClose } from 'shared/lib/hooks/useConfirmClose';

import { requestJson } from './requestJson';

interface GitlabProject {
  id: string;
  path: string;
  name: string;
}

interface GitlabBoard {
  id: string;
  name: string;
  lists: string[];
}

interface Props {
  integration: Integration | null;
  onClose: () => void;
  basePath: string;
}

const NO_BOARD = '';

// Which GitLab projects are trackers, and whose board's label lists are each one's columns.
export const GitlabTrackersModal = ({ integration, onClose, basePath }: Props) => {
  const [projects, setProjects] = useState<GitlabProject[] | null>(null);
  const [chosen, setChosen] = useState<string[]>([]);
  const [boardFor, setBoardFor] = useState<Record<string, string>>({});
  const [boards, setBoards] = useState<Record<string, GitlabBoard[]>>({});
  const [initial, setInitial] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const base = integration ? `${basePath}/${integration.id}` : '';

  const loadBoards = useCallback(
    (projectId: string) => {
      if (!base || boards[projectId]) return;
      requestJson(
        `${base}/gitlab_boards?gitlab_project_id=${projectId}`,
        { method: 'GET' },
        'GitLab rejected the request',
      )
        .then((result) => setBoards((all) => ({ ...all, [projectId]: result.boards as GitlabBoard[] })))
        .catch(() => setBoards((all) => ({ ...all, [projectId]: [] })));
    },
    [base, boards],
  );

  useEffect(() => {
    if (!integration) return;
    let cancelled = false;
    setProjects(null);
    setError(null);
    requestJson(`${basePath}/${integration.id}/gitlab_projects`, { method: 'GET' }, 'GitLab rejected the request')
      .then((result) => {
        if (cancelled) return;
        const selected = result.selected as { id: string; board_id?: string | null }[];
        setProjects(result.projects as GitlabProject[]);
        setChosen(selected.map((s) => s.id));
        const map = Object.fromEntries(selected.map((s) => [s.id, s.board_id ?? NO_BOARD]));
        setBoardFor(map);
        setInitial(JSON.stringify(map));
      })
      .catch((e) => !cancelled && setError(e instanceof Error ? e.message : 'Could not list the GitLab projects'));
    return () => {
      cancelled = true;
    };
  }, [basePath, integration]);

  useEffect(() => {
    chosen.forEach(loadBoards);
  }, [chosen, loadBoards]);

  useEffect(() => {
    chosen.forEach((id) => {
      const list = boards[id];
      if (list && boardFor[id] === undefined) setBoardFor((all) => ({ ...all, [id]: list[0]?.id ?? NO_BOARD }));
    });
  }, [boards, boardFor, chosen]);

  const current = JSON.stringify(Object.fromEntries(chosen.map((id) => [id, boardFor[id] ?? NO_BOARD])));
  const requestClose = useConfirmClose(projects !== null && current !== initial, onClose);

  const save = useCallback(() => {
    if (!integration) return;
    setSaving(true);
    router.patch(
      base,
      { gitlabTrackers: chosen.map((id) => ({ projectId: id, boardId: boardFor[id] || null })) },
      {
        preserveScroll: true,
        onSuccess: onClose,
        onError: () => notifications.show({ message: 'Failed to save the GitLab issue boards', color: 'red' }),
        onFinish: () => setSaving(false),
      },
    );
  }, [base, boardFor, chosen, integration, onClose]);

  const nameOf = (id: string) => projects?.find((p) => p.id === id)?.path ?? id;

  return (
    <Modal opened={!!integration} onClose={requestClose} title="GitLab issue boards" size="lg">
      <Stack gap="md">
        <Text size="sm" c="dimmed">
          Each project you pick becomes a tracker. Its columns are Open, the label lists of the board you pick, and
          Closed; moving an issue swaps those labels. Without a board, an issue is just open or closed.
        </Text>
        {error && (
          <Alert color="red" icon={<IconAlertCircle size={16} />}>
            {error}
          </Alert>
        )}
        {projects === null && !error && <Loader size="sm" aria-label="Loading projects" />}
        {projects && (
          <MultiSelect
            label="GitLab projects"
            description="A project you remove is detached."
            data={projects.map((p) => ({ value: p.id, label: p.path }))}
            value={chosen}
            onChange={setChosen}
            searchable
          />
        )}
        {chosen.map((id) => (
          <Select
            key={id}
            label={`Board for ${nameOf(id)}`}
            data={[
              ...(boards[id] ?? []).map((b) => ({
                value: b.id,
                label: b.lists.length ? `${b.name} — ${b.lists.join(', ')}` : `${b.name} — no label lists`,
              })),
              { value: NO_BOARD, label: 'No board — open and closed only' },
            ]}
            value={boardFor[id] ?? NO_BOARD}
            onChange={(v) => setBoardFor((all) => ({ ...all, [id]: v ?? NO_BOARD }))}
            disabled={!boards[id]}
            allowDeselect={false}
          />
        ))}
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
