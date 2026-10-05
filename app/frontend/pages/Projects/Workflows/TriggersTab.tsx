import { Loader } from '@mantine/core';
import { IconBolt, IconClock, IconColumns, IconMessage, IconTicket, IconWebhook } from '@tabler/icons-react';
import { useCallback, useEffect, useState } from 'react';

import { apiFetch } from 'shared/lib/apiFetch';
import { isAttached, type TrackerOption } from 'shared/resources/triggers/trackerTrigger';
import { TriggerCards } from 'shared/resources/triggers/TriggerCards';
import { TriggerFormPanel } from 'shared/resources/triggers/TriggerFormPanel';
import type { ChatProviderOption, Trigger, TriggerColumnOption } from 'shared/resources/triggers/types';
import { apiV1ProjectWorkflowTriggerPath, apiV1ProjectWorkflowTriggersPath } from 'shared/routes';

export type { Trigger } from 'shared/resources/triggers/types';

interface TriggersTabProps {
  projectId: number;
  workflowId: number;
  columns: TriggerColumnOption[];
  trackers?: TrackerOption[];
  chatProviders?: ChatProviderOption[];
  readOnly: boolean;
}

export function TriggersTab({
  projectId,
  workflowId,
  columns,
  trackers = [],
  chatProviders = [],
  readOnly,
}: TriggersTabProps) {
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
      try {
        const url = apiV1ProjectWorkflowTriggerPath(
          projectId,
          workflowId,
          t.id,
          t.kind === 'column' ? { kind: 'column' } : {},
        );
        const res = await apiFetch(url, { method: 'DELETE' });
        if (res.ok) {
          setTriggers((prev) => prev.filter((x) => x.id !== t.id || x.kind !== t.kind));
        } else {
          console.error('Failed to delete trigger:', res.statusText);
        }
      } catch (error) {
        console.error('Error deleting trigger:', error);
      }
    },
    [projectId, workflowId],
  );

  const toggleEnabled = useCallback(
    async (t: Trigger, enabled: boolean) => {
      try {
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
        } else {
          console.error('Failed to toggle trigger:', res.statusText);
          // Revert the UI state on failure
          setTriggers((prev) =>
            prev.map((x) => (x.id === t.id && x.kind === t.kind ? { ...x, enabled: !enabled } : x)),
          );
        }
      } catch (error) {
        console.error('Error toggling trigger:', error);
        // Revert the UI state on failure
        setTriggers((prev) => prev.map((x) => (x.id === t.id && x.kind === t.kind ? { ...x, enabled: !enabled } : x)));
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
          Any enabled trigger can start a run. Off-board triggers (Slack, webhook, tracker) decide what task the run is
          about via <strong style={{ color: 'var(--text-2)' }}>subject</strong>.
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
                    kind: 'chat',
                    icon: IconMessage,
                    name: 'Chat message',
                    desc: 'When someone mentions the bot in Slack or Teams',
                  },
                  {
                    kind: 'webhook',
                    icon: IconWebhook,
                    name: 'Incoming webhook',
                    desc: 'When an authenticated request arrives',
                  },
                  ...(trackers.some(isAttached)
                    ? [
                        {
                          kind: 'tracker',
                          icon: IconTicket,
                          name: 'Task tracker event',
                          desc: 'When an issue is created, moves to a status or gets a comment',
                        },
                      ]
                    : []),
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
          <TriggerCards
            triggers={triggers}
            trackers={trackers}
            chatProviders={chatProviders}
            readOnly={readOnly}
            onEdit={openEdit}
            onDelete={remove}
            onToggle={toggleEnabled}
            onAdd={() => openAdd()}
          />
        )}
      </div>

      {/* Right-side panel */}
      {panelOpen && !readOnly && (
        <TriggerFormPanel
          projectId={projectId}
          workflowId={workflowId}
          columns={columns}
          trackers={trackers}
          chatProviders={chatProviders}
          editing={editingTrigger}
          defaultKind={defaultKind}
          onClose={closePanel}
          onSaved={onSaved}
        />
      )}
    </div>
  );
}
