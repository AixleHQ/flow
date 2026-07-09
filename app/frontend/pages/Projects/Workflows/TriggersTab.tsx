import { Loader, Switch } from '@mantine/core';
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
    <div style={{ position: 'relative', display: 'flex', height: '100%' }}>
      {/* Main content */}
      <div style={{ flex: 1, overflow: 'auto', padding: '28px 32px' }}>
        {/* Heading */}
        <div
          style={{
            fontSize: 16,
            fontWeight: 700,
            color: 'var(--text-1)',
            letterSpacing: '-0.02em',
            marginBottom: 4,
          }}
        >
          Triggers <span style={{ color: 'var(--text-3)', fontWeight: 400 }}>— how this workflow launches</span>
        </div>
        <div style={{ fontSize: 13, color: 'var(--text-2)', marginBottom: 20 }}>
          Any enabled trigger can start a run. Off-board triggers (Slack, webhook) decide what task the run is about via{' '}
          <strong style={{ color: 'var(--text-2)' }}>subject</strong>.
        </div>

        {loading ? (
          <div style={{ display: 'flex', justifyContent: 'center', padding: '48px 0' }}>
            <Loader size="sm" />
          </div>
        ) : isEmpty ? (
          /* Empty state */
          <div style={{ maxWidth: 640, margin: '48px auto 0', textAlign: 'center' }}>
            <div
              style={{
                width: 40,
                height: 40,
                borderRadius: 8,
                background: 'var(--bg-card)',
                border: '1px solid var(--border)',
                color: 'var(--text-2)',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                margin: '0 auto 16px',
              }}
            >
              <IconBolt size={18} />
            </div>
            <div style={{ fontSize: 16, fontWeight: 600, color: 'var(--text-1)', marginBottom: 6 }}>
              Add your first trigger
            </div>
            <div style={{ fontSize: 12, color: 'var(--text-2)', lineHeight: 1.6, marginBottom: 24 }}>
              Choose how this workflow should launch. You can add more than one — any enabled trigger starts a run.
            </div>
            {!readOnly && (
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10, textAlign: 'left' }}>
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
                    <div
                      key={opt.kind}
                      onClick={() => openAdd(opt.kind)}
                      style={{
                        display: 'flex',
                        alignItems: 'center',
                        gap: 12,
                        padding: '14px 16px',
                        background: 'var(--bg-card)',
                        border: '1px solid var(--border)',
                        borderRadius: 8,
                        cursor: 'pointer',
                        transition: 'all 0.12s',
                      }}
                      onMouseEnter={(e) => {
                        (e.currentTarget as HTMLElement).style.borderColor = 'var(--accent-muted)';
                        (e.currentTarget as HTMLElement).style.background = 'var(--bg-hover)';
                      }}
                      onMouseLeave={(e) => {
                        (e.currentTarget as HTMLElement).style.borderColor = 'var(--border)';
                        (e.currentTarget as HTMLElement).style.background = 'var(--bg-card)';
                      }}
                    >
                      <div
                        style={{
                          width: 32,
                          height: 32,
                          borderRadius: 8,
                          background: 'var(--bg-card)',
                          border: '1px solid var(--border)',
                          color: 'var(--text-2)',
                          display: 'flex',
                          alignItems: 'center',
                          justifyContent: 'center',
                          flexShrink: 0,
                        }}
                      >
                        <Icon size={16} />
                      </div>
                      <div>
                        <div style={{ fontSize: 13, fontWeight: 600, color: 'var(--text-1)' }}>{opt.name}</div>
                        <div style={{ fontSize: 12, color: 'var(--text-2)', marginTop: 2 }}>{opt.desc}</div>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        ) : (
          /* Card grid */
          <div
            style={{
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))',
              gap: 10,
            }}
          >
            {triggers.map((t) => {
              const Icon = TG_ICONS[t.kind] ?? IconBolt;
              const isDisabled = t.enabled === false;
              return (
                <div
                  key={`${t.kind}-${t.id}`}
                  style={{
                    display: 'flex',
                    flexDirection: 'column',
                    gap: 10,
                    padding: '14px 16px',
                    background: 'var(--bg-card)',
                    border: '1px solid var(--border)',
                    borderRadius: 8,
                    opacity: isDisabled ? 0.55 : 1,
                    transition: 'opacity 0.15s, border-color 0.15s',
                  }}
                >
                  {/* Head row */}
                  <div style={{ display: 'flex', alignItems: 'center', gap: 10, minWidth: 0 }}>
                    <div
                      style={{
                        width: 32,
                        height: 32,
                        borderRadius: 8,
                        background: 'var(--bg-card)',
                        border: '1px solid var(--border)',
                        color: 'var(--text-2)',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        flexShrink: 0,
                      }}
                    >
                      <Icon size={16} />
                    </div>
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div
                        style={{
                          fontSize: 14,
                          fontWeight: 600,
                          color: 'var(--text-1)',
                          overflow: 'hidden',
                          textOverflow: 'ellipsis',
                          whiteSpace: 'nowrap',
                        }}
                      >
                        {triggerTitle(t)}
                      </div>
                      <div
                        style={{
                          fontSize: 12,
                          color: 'var(--text-2)',
                          marginTop: 2,
                          overflow: 'hidden',
                          textOverflow: 'ellipsis',
                          whiteSpace: 'nowrap',
                        }}
                      >
                        {triggerMeta(t)}
                      </div>
                    </div>
                  </div>

                  {/* Foot row */}
                  <div
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'space-between',
                      gap: 8,
                      marginTop: 'auto',
                    }}
                  >
                    {/* Event badge */}
                    <div style={{ display: 'flex', alignItems: 'center', gap: 6, minWidth: 0, flexWrap: 'wrap' }}>
                      <span
                        style={{
                          fontSize: 10,
                          fontWeight: 600,
                          letterSpacing: '0.04em',
                          color: 'var(--text-3)',
                          background: 'var(--bg-raised)',
                          border: '1px solid var(--border)',
                          padding: '2px 8px',
                          borderRadius: 4,
                          textTransform: 'uppercase',
                          flexShrink: 0,
                        }}
                      >
                        {TG_EVENTS[t.kind] ?? t.event_type}
                      </span>
                    </div>

                    {/* Actions */}
                    {!readOnly && (
                      <div style={{ display: 'flex', alignItems: 'center', gap: 4, flexShrink: 0 }}>
                        <Switch
                          size="xs"
                          checked={t.enabled !== false}
                          onChange={(e) => toggleEnabled(t, e.currentTarget.checked)}
                        />
                        <div style={{ width: 1, height: 16, background: 'var(--border)', margin: '0 4px' }} />
                        <button
                          onClick={() => openEdit(t)}
                          style={{
                            background: 'none',
                            border: 'none',
                            cursor: 'pointer',
                            color: 'var(--text-3)',
                            padding: 6,
                            borderRadius: 4,
                            display: 'flex',
                            transition: 'all 0.12s',
                          }}
                          onMouseEnter={(e) => {
                            (e.currentTarget as HTMLElement).style.color = 'var(--text-1)';
                            (e.currentTarget as HTMLElement).style.background = 'var(--bg-hover)';
                          }}
                          onMouseLeave={(e) => {
                            (e.currentTarget as HTMLElement).style.color = 'var(--text-3)';
                            (e.currentTarget as HTMLElement).style.background = 'none';
                          }}
                        >
                          <IconPencil size={14} />
                        </button>
                        <button
                          onClick={() => remove(t)}
                          style={{
                            background: 'none',
                            border: 'none',
                            cursor: 'pointer',
                            color: 'var(--text-3)',
                            padding: 6,
                            borderRadius: 4,
                            display: 'flex',
                            transition: 'all 0.12s',
                          }}
                          onMouseEnter={(e) => {
                            (e.currentTarget as HTMLElement).style.color = 'var(--err)';
                            (e.currentTarget as HTMLElement).style.background = 'var(--bg-hover)';
                          }}
                          onMouseLeave={(e) => {
                            (e.currentTarget as HTMLElement).style.color = 'var(--text-3)';
                            (e.currentTarget as HTMLElement).style.background = 'none';
                          }}
                        >
                          <IconTrash size={14} />
                        </button>
                      </div>
                    )}
                  </div>
                </div>
              );
            })}

            {/* Add a trigger tile */}
            {!readOnly && (
              <button
                onClick={() => openAdd()}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  gap: 8,
                  minHeight: 96,
                  border: '1px dashed var(--border)',
                  borderRadius: 8,
                  color: 'var(--text-2)',
                  fontSize: 13,
                  fontWeight: 500,
                  cursor: 'pointer',
                  transition: 'all 0.12s',
                  background: 'none',
                  fontFamily: 'inherit',
                }}
                onMouseEnter={(e) => {
                  (e.currentTarget as HTMLElement).style.color = 'var(--accent)';
                  (e.currentTarget as HTMLElement).style.borderColor = 'var(--accent-muted)';
                  (e.currentTarget as HTMLElement).style.background = 'var(--bg-hover)';
                }}
                onMouseLeave={(e) => {
                  (e.currentTarget as HTMLElement).style.color = 'var(--text-2)';
                  (e.currentTarget as HTMLElement).style.borderColor = 'var(--border)';
                  (e.currentTarget as HTMLElement).style.background = 'none';
                }}
              >
                <IconPlus size={16} />
                Add a trigger
              </button>
            )}
          </div>
        )}
      </div>

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
    </div>
  );
}
