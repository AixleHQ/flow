import { ActionIcon, Badge, Box, Group, Loader, Switch, Text, ThemeIcon, Tooltip } from '@mantine/core';
import {
  IconBolt,
  IconBrandSlack,
  IconClock,
  IconColumns,
  IconPencil,
  IconPlus,
  IconTrash,
  IconWebhook,
} from '@tabler/icons-react';
import cronstrue from 'cronstrue';
import { useCallback, useEffect, useState } from 'react';

import { apiFetch } from 'shared/lib/apiFetch';
import { apiV1ProjectWorkflowTriggerPath, apiV1ProjectWorkflowTriggersPath } from 'shared/routes';

import { TriggerFormPanel } from './TriggerFormPanel';

interface ColumnOption {
  id: number;
  name: string;
  boundWorkflowName?: string | null;
}

interface StepOption {
  id: number;
  name: string;
}

export interface Trigger {
  id: number;
  kind: string;
  event_type: string;
  name?: string | null;
  trigger_mode?: string;
  cooldown_seconds?: number;
  enabled?: boolean;
  column_name?: string;
  board_column_id?: number;
  subject_policy?: string;
  subject_column_id?: number | null;
  subject_title_template?: string | null;
  filter_predicate?: Record<string, unknown>;
  schedule_config?: { cron?: string; timezone?: string };
}

interface TriggersTabProps {
  projectId: number;
  workflowId: number;
  columns: ColumnOption[];
  sessions: StepOption[];
  readOnly: boolean;
}

const TG_ICONS: Record<string, typeof IconBolt> = {
  column: IconColumns,
  schedule: IconClock,
  slack: IconBrandSlack,
  webhook: IconWebhook,
};

const TG_EVENTS: Record<string, string> = {
  column: 'BOARD.COLUMN_CHANGED',
  schedule: 'SCHEDULE.CRON',
  slack: 'SLACK.MESSAGE',
  webhook: 'WEBHOOK.RECEIVED',
};

function describeCronShort(expr: string): string {
  if (!expr?.trim()) return '';
  try {
    return cronstrue.toString(expr.trim(), { throwExceptionOnParseError: true, verbose: false });
  } catch {
    return `Cron ${expr}`;
  }
}

function triggerTitle(t: Trigger): string {
  if (t.kind === 'column') return `Task enters "${t.column_name ?? 'column'}"`;
  if (t.kind === 'schedule') {
    const cron = t.schedule_config?.cron ?? '';
    return describeCronShort(cron) || `Cron ${cron}`;
  }
  if (t.kind === 'slack') {
    const pred = t.filter_predicate ?? {};
    const text = pred.text;
    if (text && typeof text === 'object') {
      const t2 = text as { op?: string; value?: string };
      if (t2.value) return `Slack message ${t2.op ?? 'contains'} "${t2.value}"`;
    }
    return 'Any Slack message';
  }
  return 'Incoming webhook';
}

function triggerMeta(t: Trigger): string {
  if (t.kind === 'column') return `${t.trigger_mode ?? 'auto'} · cooldown ${t.cooldown_seconds ?? 0}s`;
  if (t.kind === 'schedule') {
    const cfg = t.schedule_config ?? {};
    return `${cfg.cron ?? '—'} · ${cfg.timezone ?? 'UTC'}`;
  }
  if (t.kind === 'slack') {
    const pred = t.filter_predicate ?? {};
    const channel = pred.channel;
    return typeof channel === 'string' && channel ? `channel ${channel}` : 'any channel';
  }
  const pred = t.filter_predicate ?? {};
  const keys = Object.keys(pred);
  const base = `verification: ${(t as unknown as Record<string, unknown>).verification_strategy ?? 'none'}`;
  if (keys.length > 0) {
    const key = keys[0];
    const val = pred[key];
    if (val && typeof val === 'object') {
      const v = val as { op?: string; value?: unknown };
      return `${base} · when ${key} ${v.op ?? 'eq'} ${v.value}`;
    }
    return `${base} · when ${key} eq ${val}`;
  }
  return base;
}

export function TriggersTab({ projectId, workflowId, columns, sessions, readOnly }: TriggersTabProps) {
  const [triggers, setTriggers] = useState<Trigger[]>([]);
  const [loading, setLoading] = useState(false);
  const [panelOpen, setPanelOpen] = useState(false);
  const [editingTrigger, setEditingTrigger] = useState<Trigger | null>(null);
  const [defaultKind, setDefaultKind] = useState<string>('column');

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await apiFetch(apiV1ProjectWorkflowTriggersPath(projectId, workflowId));
      if (res.ok) {
        const data = await res.json();
        setTriggers(data.triggers ?? []);
      }
    } finally {
      setLoading(false);
    }
  }, [projectId, workflowId]);

  useEffect(() => {
    load();
  }, [load]);

  const remove = useCallback(
    async (t: Trigger) => {
      const url = apiV1ProjectWorkflowTriggerPath(
        projectId,
        workflowId,
        t.id,
        t.kind === 'column' ? { kind: 'column' } : {},
      );
      const res = await apiFetch(url, { method: 'DELETE' });
      if (res.ok) {
        setTriggers((prev) => prev.filter((x) => x.id !== t.id || x.kind !== t.kind));
      }
    },
    [projectId, workflowId],
  );

  const toggleEnabled = useCallback(
    async (t: Trigger, enabled: boolean) => {
      const url = apiV1ProjectWorkflowTriggerPath(
        projectId,
        workflowId,
        t.id,
        t.kind === 'column' ? { kind: 'column' } : {},
      );
      const res = await apiFetch(url, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ trigger: { enabled } }),
      });
      if (res.ok) {
        setTriggers((prev) => prev.map((x) => (x.id === t.id && x.kind === t.kind ? { ...x, enabled } : x)));
      }
    },
    [projectId, workflowId],
  );

  const openAdd = (kind?: string) => {
    setEditingTrigger(null);
    setDefaultKind(kind ?? 'column');
    setPanelOpen(true);
  };

  const openEdit = (t: Trigger) => {
    setEditingTrigger(t);
    setPanelOpen(true);
  };

  const closePanel = () => {
    setPanelOpen(false);
    setEditingTrigger(null);
  };

  const onSaved = () => {
    closePanel();
    load();
  };

  const isEmpty = !loading && triggers.length === 0;

  return (
    <Box style={{ position: 'relative', display: 'flex', height: '100%' }}>
      {/* Main content */}
      <Box style={{ flex: 1, overflow: 'auto', padding: '24px' }}>
        <Text fw={600} size="md" style={{ color: 'var(--text-1)' }} mb={4}>
          Triggers — how this workflow launches
        </Text>
        <Text size="sm" style={{ color: 'var(--text-2)' }} mb={20}>
          Any enabled trigger can start a run. Off-board triggers (Slack, webhook) decide what task the run is about via
          subject.
        </Text>

        {loading ? (
          <Group justify="center" py="xl">
            <Loader size="sm" />
          </Group>
        ) : isEmpty ? (
          /* Empty state */
          <Box ta="center" py={48}>
            <Box
              mb={16}
              style={{
                width: 48,
                height: 48,
                borderRadius: 12,
                background: 'var(--accent-dim)',
                border: '1px solid var(--accent-muted)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                margin: '0 auto 16px',
              }}
            >
              <IconBolt size={20} style={{ color: 'var(--accent)' }} />
            </Box>
            <Text fw={600} size="md" style={{ color: 'var(--text-1)' }} mb={8}>
              Add your first trigger
            </Text>
            <Text size="sm" style={{ color: 'var(--text-2)' }} mb={24} maw={420} mx="auto">
              Choose how this workflow should launch. You can add more than one — any enabled trigger starts a run.
            </Text>
            {!readOnly && (
              <Box
                style={{
                  display: 'grid',
                  gridTemplateColumns: 'repeat(2, 1fr)',
                  gap: 12,
                  maxWidth: 480,
                  margin: '0 auto',
                }}
              >
                {[
                  {
                    kind: 'column',
                    icon: IconColumns,
                    name: 'Task enters column',
                    desc: 'When a board task moves into a chosen column',
                  },
                  { kind: 'schedule', icon: IconClock, name: 'On schedule', desc: 'On a recurring cron timer' },
                  {
                    kind: 'slack',
                    icon: IconBrandSlack,
                    name: 'Slack message',
                    desc: 'When a matching message is posted',
                  },
                  {
                    kind: 'webhook',
                    icon: IconWebhook,
                    name: 'Incoming webhook',
                    desc: 'When an authenticated request arrives',
                  },
                ].map((opt) => {
                  const Icon = opt.icon;
                  return (
                    <Box
                      key={opt.kind}
                      p={16}
                      onClick={() => openAdd(opt.kind)}
                      style={{
                        background: 'var(--bg-card)',
                        border: '1px solid var(--border)',
                        borderRadius: 8,
                        cursor: 'pointer',
                        textAlign: 'left',
                        transition: 'border-color 0.15s',
                      }}
                      onMouseEnter={(e) => ((e.currentTarget as HTMLElement).style.borderColor = 'var(--border-mid)')}
                      onMouseLeave={(e) => ((e.currentTarget as HTMLElement).style.borderColor = 'var(--border)')}
                    >
                      <Icon size={18} style={{ color: 'var(--accent)', marginBottom: 8 }} />
                      <Text size="sm" fw={600} style={{ color: 'var(--text-1)' }} mb={4}>
                        {opt.name}
                      </Text>
                      <Text size="xs" style={{ color: 'var(--text-2)' }}>
                        {opt.desc}
                      </Text>
                    </Box>
                  );
                })}
              </Box>
            )}
          </Box>
        ) : (
          /* Card grid */
          <Box>
            <Box
              style={{
                display: 'grid',
                gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))',
                gap: 12,
              }}
            >
              {triggers.map((t) => {
                const Icon = TG_ICONS[t.kind] ?? IconBolt;
                const isDisabled = t.enabled === false;
                return (
                  <Box
                    key={`${t.kind}-${t.id}`}
                    p={16}
                    style={{
                      background: 'var(--bg-card)',
                      border: '1px solid var(--border)',
                      borderRadius: 8,
                      opacity: isDisabled ? 0.6 : 1,
                    }}
                  >
                    {/* Top row */}
                    <Group gap="sm" mb={12} wrap="nowrap">
                      <ThemeIcon
                        size={32}
                        radius="md"
                        style={{
                          background: 'var(--accent-dim)',
                          border: '1px solid var(--accent-muted)',
                          flexShrink: 0,
                        }}
                      >
                        <Icon size={16} style={{ color: 'var(--accent)' }} />
                      </ThemeIcon>
                      <Box style={{ flex: 1, minWidth: 0 }}>
                        <Text size="sm" fw={600} truncate style={{ color: 'var(--text-1)' }}>
                          {triggerTitle(t)}
                        </Text>
                        <Text size="xs" truncate style={{ color: 'var(--text-2)' }}>
                          {triggerMeta(t)}
                        </Text>
                      </Box>
                    </Group>

                    {/* Bottom row */}
                    <Group justify="space-between" wrap="nowrap">
                      <Group gap={6}>
                        <Badge
                          size="xs"
                          variant="outline"
                          style={{ borderColor: 'var(--border-mid)', color: 'var(--text-2)' }}
                        >
                          {TG_EVENTS[t.kind] ?? t.event_type}
                        </Badge>
                        {isDisabled && (
                          <Badge size="xs" color="gray" variant="outline">
                            Disabled
                          </Badge>
                        )}
                      </Group>
                      <Group gap={4} wrap="nowrap">
                        {!readOnly && t.kind !== 'column' && (
                          <Tooltip label={t.enabled === false ? 'Enable' : 'Disable'}>
                            <Switch
                              size="xs"
                              checked={t.enabled !== false}
                              onChange={(e) => toggleEnabled(t, e.currentTarget.checked)}
                            />
                          </Tooltip>
                        )}
                        {!readOnly && (
                          <>
                            <ActionIcon
                              size="sm"
                              variant="subtle"
                              style={{ color: 'var(--text-2)' }}
                              onClick={() => openEdit(t)}
                            >
                              <IconPencil size={14} />
                            </ActionIcon>
                            <ActionIcon size="sm" variant="subtle" color="red" onClick={() => remove(t)}>
                              <IconTrash size={14} />
                            </ActionIcon>
                          </>
                        )}
                      </Group>
                    </Group>
                  </Box>
                );
              })}

              {/* Add a trigger tile */}
              {!readOnly && (
                <Box
                  p={16}
                  onClick={() => openAdd()}
                  style={{
                    background: 'transparent',
                    border: '1px dashed var(--border-mid)',
                    borderRadius: 8,
                    cursor: 'pointer',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center',
                    gap: 8,
                    minHeight: 80,
                    transition: 'border-color 0.15s',
                  }}
                  onMouseEnter={(e) => ((e.currentTarget as HTMLElement).style.borderColor = 'var(--accent-muted)')}
                  onMouseLeave={(e) => ((e.currentTarget as HTMLElement).style.borderColor = 'var(--border-mid)')}
                >
                  <IconPlus size={16} style={{ color: 'var(--text-2)' }} />
                  <Text size="sm" style={{ color: 'var(--text-2)' }}>
                    Add a trigger
                  </Text>
                </Box>
              )}
            </Box>
          </Box>
        )}
      </Box>

      {/* Right-side panel */}
      {panelOpen && !readOnly && (
        <TriggerFormPanel
          projectId={projectId}
          workflowId={workflowId}
          columns={columns}
          sessions={sessions}
          editing={editingTrigger}
          defaultKind={defaultKind}
          onClose={closePanel}
          onSaved={onSaved}
        />
      )}
    </Box>
  );
}
