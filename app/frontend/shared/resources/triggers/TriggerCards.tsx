import { Link } from '@inertiajs/react';
import { Switch } from '@mantine/core';
import {
  IconBolt,
  IconBrandSlack,
  IconClock,
  IconColumns,
  IconMessage,
  IconPencil,
  IconPlus,
  IconTicket,
  IconTrash,
  IconUser,
  IconWebhook,
} from '@tabler/icons-react';
import cronstrue from 'cronstrue';

import { isAttached, TRACKER_EVENT_OPTIONS, type TrackerOption } from './trackerTrigger';
import type { Trigger } from './types';

// Where a run can come from, as the Triggers page groups and filters them.
export const SOURCE_LABELS: Record<string, string> = {
  board: 'Board column',
  chat: 'Chat',
  tracker: 'Task tracker',
  schedule: 'Schedule',
  webhook: 'Webhook',
  event: 'Custom event',
};

// A chat trigger's messenger. Another one is an entry here and in the serializer's map.
export const CHAT_PROVIDER_LABELS: Record<string, string> = {
  slack: 'Slack',
};

const CHAT_ICONS: Record<string, typeof IconBolt> = {
  slack: IconBrandSlack,
};

const SOURCE_ICONS: Record<string, typeof IconBolt> = {
  board: IconColumns,
  schedule: IconClock,
  chat: IconMessage,
  webhook: IconWebhook,
  tracker: IconTicket,
};

const SOURCE_BADGES: Record<string, string> = {
  board: 'BOARD.COLUMN_CHANGED',
  schedule: 'SCHEDULE.CRON',
  webhook: 'WEBHOOK.RECEIVED',
};

export function triggerSource(t: Trigger): string {
  if (t.source) return t.source;
  if (t.kind === 'column') return 'board';
  if (t.kind === 'slack') return 'chat';
  return t.kind;
}

function chatLabel(t: Trigger): string {
  const provider = t.chat_provider ?? (t.kind === 'slack' ? 'slack' : '');
  return CHAT_PROVIDER_LABELS[provider] ?? 'Chat';
}

function describeCronShort(expr: string): string {
  if (!expr?.trim()) return '';
  try {
    return cronstrue.toString(expr.trim(), { throwExceptionOnParseError: true, verbose: false });
  } catch {
    return `Cron ${expr}`;
  }
}

export function triggerTitle(t: Trigger): string {
  const source = triggerSource(t);
  if (source !== 'chat' && t.name?.trim()) return t.name.trim();
  if (source === 'board') return `Task enters "${t.column_name ?? 'column'}"`;
  if (source === 'schedule') {
    const cron = t.schedule_config?.cron ?? '';
    return describeCronShort(cron) || `Cron ${cron}`;
  }
  if (source === 'chat') {
    const text = t.filter_predicate?.text;
    if (text && typeof text === 'object') {
      const t2 = text as { op?: string; value?: string };
      if (t2.value) return `${chatLabel(t)} message ${t2.op ?? 'contains'} "${t2.value}"`;
    }
    return `Any ${chatLabel(t)} message`;
  }
  if (source === 'tracker') {
    const label = TRACKER_EVENT_OPTIONS.find((o) => o.value === t.event_type)?.label ?? t.event_type;
    const moves = (t.filter_predicate?.['change.to.name'] as { value?: unknown } | undefined)?.value;
    if (Array.isArray(moves) && moves.length > 0) return `Issue moves to ${moves.join(', ')}`;
    if (t.filter_predicate?.['comment.mentions_me'] === true) return 'Aixle is mentioned in a comment';
    return label;
  }
  if (source === 'event') return `Event ${t.event_type}`;
  return 'Incoming webhook';
}

// Off-board triggers fire unattended, so the run belongs to — and uses the
// credentials of — whoever added the trigger. A column trigger's run belongs to
// the person the card puts on it, so its creator is shown as provenance only.
const OFF_BOARD_SOURCES = new Set(['chat', 'schedule', 'webhook', 'event', 'tracker']);

function creatorLabel(t: Trigger): string {
  const name = t.created_by?.name;
  const runsAsCreator = OFF_BOARD_SOURCES.has(triggerSource(t));
  if (!name) return runsAsCreator ? 'No creator — this trigger cannot start a run' : 'Created by Unknown';
  return runsAsCreator ? `Runs as ${name}` : `Created by ${name}`;
}

// A missing creator only breaks the off-board kinds — a column trigger still runs
// under the person the card is on, so an unknown creator there is just a blank.
function creatorTone(t: Trigger): string {
  if (t.created_by) return 'var(--text-2)';
  return OFF_BOARD_SOURCES.has(triggerSource(t)) ? 'var(--err)' : 'var(--text-3)';
}

const AIXLE_CHANGE_LABELS: Record<string, string> = {
  ignore: 'ignores Aixle changes',
  other_workflows: 'chains from other workflows',
  always: 'follows Aixle changes',
};

export function triggerMeta(t: Trigger, trackers: TrackerOption[] = []): string {
  const source = triggerSource(t);
  if (source === 'tracker') {
    const tracker = trackers.find((tr) => tr.id === t.project_tracker_id);
    let scope = 'any tracker';
    if (t.project_tracker_id) scope = tracker ? tracker.handle : 'detached tracker';
    if (tracker && !isAttached(tracker)) scope = `${tracker.handle} (detached, not firing)`;
    return `${scope} · ${AIXLE_CHANGE_LABELS[t.aixle_changes ?? 'ignore'] ?? t.aixle_changes}`;
  }
  if (source === 'board') return `${t.trigger_mode ?? 'auto'} · cooldown ${t.cooldown_seconds ?? 0}s`;
  if (source === 'schedule') {
    const cfg = t.schedule_config ?? {};
    return `${cfg.cron ?? '—'} · ${cfg.timezone ?? 'UTC'}`;
  }
  if (source === 'chat') {
    const channel = t.filter_predicate?.channel;
    return typeof channel === 'string' && channel ? `channel ${channel}` : 'any channel';
  }
  const pred = t.filter_predicate ?? {};
  const keys = Object.keys(pred);
  const base = source === 'webhook' ? `verification: ${t.verification_strategy ?? 'none'}` : t.event_type;
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

const iconButton = {
  background: 'none',
  border: 'none',
  cursor: 'pointer',
  color: 'var(--text-3)',
  padding: 6,
  borderRadius: 4,
  display: 'flex',
  transition: 'all 0.12s',
} as const;

interface TriggerCardsProps {
  triggers: Trigger[];
  trackers?: TrackerOption[];
  readOnly: boolean;
  onEdit: (t: Trigger) => void;
  onDelete: (t: Trigger) => void;
  onToggle: (t: Trigger, enabled: boolean) => void;
  // Shown on the project's Triggers page, where cards of several workflows sit together.
  workflowHref?: (t: Trigger) => string | null;
  onAdd?: () => void;
}

export function TriggerCards({
  triggers,
  trackers = [],
  readOnly,
  onEdit,
  onDelete,
  onToggle,
  workflowHref,
  onAdd,
}: TriggerCardsProps) {
  return (
    <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(280px, 1fr))', gap: 10 }}>
      {triggers.map((t) => {
        const source = triggerSource(t);
        const Icon = (source === 'chat' ? CHAT_ICONS[t.chat_provider ?? 'slack'] : null) ?? SOURCE_ICONS[source] ?? IconBolt;
        const isDisabled = t.enabled === false;
        const href = workflowHref?.(t);
        const title = triggerTitle(t);
        return (
          <article
            key={`${t.kind}-${t.id}`}
            aria-label={title}
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
                  {title}
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
                  {triggerMeta(t, trackers)}
                </div>
              </div>
            </div>

            {href && (
              <div style={{ fontSize: 12, color: 'var(--text-2)', minWidth: 0 }}>
                Starts{' '}
                <Link href={href} style={{ color: 'var(--accent-text)' }}>
                  {t.workflow_name ?? 'workflow'}
                </Link>
              </div>
            )}

            <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 12, color: creatorTone(t), minWidth: 0 }}>
              <IconUser size={13} style={{ flexShrink: 0 }} />
              {/* The card is narrow enough to clip the longer labels — keep the full text reachable. */}
              <span title={creatorLabel(t)} style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                {creatorLabel(t)}
              </span>
            </div>

            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8, marginTop: 'auto' }}>
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
                  {source === 'chat'
                    ? `${(t.chat_provider ?? 'slack').toUpperCase()}.MESSAGE`
                    : (SOURCE_BADGES[source] ?? t.event_type)}
                </span>
              </div>

              {!readOnly && (
                <div style={{ display: 'flex', alignItems: 'center', gap: 4, flexShrink: 0 }}>
                  {/* A board-column trigger has no off switch: removing it is how it stops. */}
                  {source !== 'board' && (
                    <>
                      <Switch
                        size="xs"
                        aria-label={`Enable ${title}`}
                        checked={t.enabled !== false}
                        onChange={(e) => onToggle(t, e.currentTarget.checked)}
                      />
                      <div style={{ width: 1, height: 16, background: 'var(--border)', margin: '0 4px' }} />
                    </>
                  )}
                  <button aria-label={`Edit ${title}`} onClick={() => onEdit(t)} style={iconButton}>
                    <IconPencil size={14} />
                  </button>
                  <button aria-label={`Delete ${title}`} onClick={() => onDelete(t)} style={iconButton}>
                    <IconTrash size={14} />
                  </button>
                </div>
              )}
            </div>
          </article>
        );
      })}

      {!readOnly && onAdd && (
        <button
          onClick={onAdd}
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
            background: 'none',
            fontFamily: 'inherit',
          }}
        >
          <IconPlus size={16} />
          Add a trigger
        </button>
      )}
    </div>
  );
}
