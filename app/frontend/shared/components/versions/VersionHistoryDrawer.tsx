import { Alert, Badge, Box, Button, Drawer, Group, Loader, Modal, SegmentedControl, Stack, Text } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconArrowBackUp, IconHistory } from '@tabler/icons-react';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';

import type { EntityVersion, EntityVersionDetail } from '@/types/generated';

import { ApiError, apiRequest, notifyApiFailure } from 'shared/lib/apiFetch';
import { formatDateTime } from 'shared/lib/formatDate';
import { diffSnapshots } from 'shared/lib/versionDiff';
import { describeVersion, revertWarnings } from 'shared/lib/versionHistory';
import { VERSION_SCHEMAS, type VersionableType } from 'shared/lib/versionSchemas';

import { VersionDiff } from './VersionDiff';

interface VersionHistoryDrawerProps {
  opened: boolean;
  onClose: () => void;
  projectId: number;
  versionableType: VersionableType;
  versionableId: number;
  /** What the history is of, e.g. the agent's title. */
  title: string;
  canRevert: boolean;
  /** Called after a revert lands, so the page can reload the entity. */
  onReverted?: () => void;
}

interface VersionPage {
  versions: EntityVersion[];
  nextBefore: number | null;
  currentVersionNumber: number;
}

const SOURCE_LABELS: Record<EntityVersion['source'], string> = {
  ui: '',
  api: 'via API',
  mcp: 'via MCP',
  builder: 'by Aixle Builder',
  system: 'by the system',
};

function versionsPath(projectId: number, type: VersionableType, id: number, before: number | null) {
  const query = new URLSearchParams({ versionable_type: type, versionable_id: String(id) });
  if (before !== null) query.set('before', String(before));
  return `/api/v1/projects/${projectId}/entity_versions?${query.toString()}`;
}

function VersionRow({
  version,
  current,
  selected,
  onSelect,
}: {
  version: EntityVersion;
  current: boolean;
  selected: boolean;
  onSelect: () => void;
}) {
  const source = SOURCE_LABELS[version.source];
  return (
    <Box
      component="button"
      type="button"
      onClick={onSelect}
      aria-pressed={selected}
      p="sm"
      style={{
        textAlign: 'left',
        width: '100%',
        cursor: 'pointer',
        background: selected ? 'var(--app-action-selected)' : 'var(--app-bg-paper)',
        border: '1px solid var(--app-border-default)',
        borderRadius: 'var(--mantine-radius-sm)',
        color: 'inherit',
      }}
    >
      <Group justify="space-between" wrap="nowrap">
        <Group gap={8} wrap="nowrap">
          <Badge variant="light" color="gray" size="sm">
            v{version.number}
          </Badge>
          <Text fz={14} fw={500}>
            {describeVersion(version)}
          </Text>
          {current && (
            <Badge variant="light" color="green" size="sm">
              current
            </Badge>
          )}
        </Group>
        <Text fz={12} c="dimmed" style={{ whiteSpace: 'nowrap' }}>
          {formatDateTime(version.createdAt)}
        </Text>
      </Group>
      <Text fz={12} c="dimmed" mt={2}>
        {[version.author?.name ?? (version.source === 'system' ? null : 'Unknown'), source].filter(Boolean).join(' ')}
      </Text>
    </Box>
  );
}

/** An entity's version history: the timeline, each version's diff, and revert. */
export function VersionHistoryDrawer({
  opened,
  onClose,
  projectId,
  versionableType,
  versionableId,
  title,
  canRevert,
  onReverted,
}: VersionHistoryDrawerProps) {
  const [versions, setVersions] = useState<EntityVersion[]>([]);
  const [nextBefore, setNextBefore] = useState<number | null>(null);
  const [currentNumber, setCurrentNumber] = useState(0);
  const [loadingPage, setLoadingPage] = useState(false);
  const [selected, setSelected] = useState<EntityVersion | null>(null);
  const [detail, setDetail] = useState<EntityVersionDetail | null>(null);
  const [compareWith, setCompareWith] = useState<'previous' | 'current'>('previous');
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [reverting, setReverting] = useState(false);
  const sentinel = useRef<HTMLDivElement | null>(null);

  const loadPage = useCallback(
    async (before: number | null) => {
      setLoadingPage(true);
      try {
        const page = await apiRequest<VersionPage>(versionsPath(projectId, versionableType, versionableId, before));
        setVersions((prev) => (before === null ? page.versions : [...prev, ...page.versions]));
        setNextBefore(page.nextBefore);
        setCurrentNumber(page.currentVersionNumber);
      } catch (error) {
        notifyApiFailure(error, 'Could not load the version history');
      } finally {
        setLoadingPage(false);
      }
    },
    [projectId, versionableType, versionableId],
  );

  useEffect(() => {
    if (!opened) return;
    setSelected(null);
    setDetail(null);
    void loadPage(null);
  }, [opened, loadPage]);

  useEffect(() => {
    const node = sentinel.current;
    if (!node || nextBefore === null) return;
    const observer = new IntersectionObserver((entries) => {
      if (entries.some((entry) => entry.isIntersecting) && !loadingPage) void loadPage(nextBefore);
    });
    observer.observe(node);
    return () => observer.disconnect();
  }, [nextBefore, loadingPage, loadPage]);

  const select = async (version: EntityVersion) => {
    setSelected(version);
    setDetail(null);
    setCompareWith('previous');
    try {
      setDetail(await apiRequest<EntityVersionDetail>(`/api/v1/projects/${projectId}/entity_versions/${version.id}`));
    } catch (error) {
      notifyApiFailure(error, 'Could not load this version');
    }
  };

  const schema = VERSION_SCHEMAS[versionableType];
  const changes = useMemo(() => {
    if (!detail) return [];
    return compareWith === 'previous'
      ? diffSnapshots(schema, detail.previousSnapshot, detail.snapshot, detail.references)
      : diffSnapshots(schema, detail.currentSnapshot, detail.snapshot, detail.references);
  }, [detail, compareWith, schema]);

  const revertChanges = useMemo(
    () => (detail ? diffSnapshots(schema, detail.currentSnapshot, detail.snapshot, detail.references) : []),
    [detail, schema],
  );
  const warnings = useMemo(
    () => (detail ? revertWarnings(versionableType, detail.snapshot, detail.currentSnapshot, detail.references) : []),
    [detail, versionableType],
  );

  const revert = async () => {
    if (!detail) return;
    setReverting(true);
    try {
      const created = await apiRequest<EntityVersion>(
        `/api/v1/projects/${projectId}/entity_versions/${detail.id}/revert`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ base_version: detail.currentVersionNumber }),
        },
      );
      notifications.show({ color: 'green', message: `Reverted to v${detail.number} — saved as v${created.number}` });
      setConfirmOpen(false);
      onReverted?.();
      await loadPage(null);
      setSelected(null);
      setDetail(null);
    } catch (error) {
      if (error instanceof ApiError && error.status === 409) await loadPage(null);
      notifyApiFailure(error, 'The revert did not go through');
    } finally {
      setReverting(false);
    }
  };

  const isCurrent = selected?.number === currentNumber;

  return (
    <Drawer
      opened={opened}
      onClose={onClose}
      position="right"
      size={720}
      title={
        <Group gap={8}>
          <IconHistory size={18} />
          <Text fw={600}>Version history — {title}</Text>
        </Group>
      }
    >
      <Stack gap="sm">
        {versions.length === 0 && !loadingPage && (
          <Text fz={14} c="dimmed">
            No versions yet — the first save starts the history.
          </Text>
        )}
        {versions.map((version) => (
          <Box key={version.id}>
            <VersionRow
              version={version}
              current={version.number === currentNumber}
              selected={selected?.id === version.id}
              onSelect={() => void select(version)}
            />
            {selected?.id === version.id && (
              <Box p="sm" style={{ borderLeft: '2px solid var(--app-border-strong)', marginLeft: 8 }}>
                {!detail ? (
                  <Loader size="sm" />
                ) : (
                  <Stack gap="sm">
                    <Group justify="space-between">
                      <SegmentedControl
                        size="xs"
                        value={compareWith}
                        onChange={(value) => setCompareWith(value as 'previous' | 'current')}
                        data={[
                          { value: 'previous', label: 'Changes in this version' },
                          { value: 'current', label: 'Compared with current' },
                        ]}
                      />
                      {canRevert && !isCurrent && (
                        <Button
                          size="xs"
                          variant="light"
                          leftSection={<IconArrowBackUp size={14} />}
                          onClick={() => setConfirmOpen(true)}
                        >
                          Revert to v{version.number}
                        </Button>
                      )}
                    </Group>
                    <VersionDiff changes={changes} />
                  </Stack>
                )}
              </Box>
            )}
          </Box>
        ))}
        <div ref={sentinel} />
        {loadingPage && <Loader size="sm" />}
        {nextBefore !== null && !loadingPage && (
          <Button variant="subtle" onClick={() => void loadPage(nextBefore)}>
            Load older versions
          </Button>
        )}
      </Stack>

      <Modal
        opened={confirmOpen}
        onClose={() => setConfirmOpen(false)}
        title={`Revert to v${detail?.number ?? ''}?`}
        size="lg"
      >
        <Stack gap="md">
          <Text fz={14} c="dimmed">
            The current version stays in the history. Reverting saves v{detail?.number}&apos;s content as a new version;
            this is what changes:
          </Text>
          {warnings.map((warning) => (
            <Alert key={warning} color="yellow" variant="light">
              {warning}
            </Alert>
          ))}
          <VersionDiff changes={revertChanges} />
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setConfirmOpen(false)} disabled={reverting}>
              Cancel
            </Button>
            <Button onClick={() => void revert()} loading={reverting}>
              Revert
            </Button>
          </Group>
        </Stack>
      </Modal>
    </Drawer>
  );
}
