import cronstrue from 'cronstrue';

import { isAttached, TRACKER_EVENT_OPTIONS, type TrackerOption } from './trackerTrigger';
import type { ChatProviderOption, Trigger } from './types';

// Where a run can come from, as the Triggers page groups and filters them.
export const SOURCE_LABELS: Record<string, string> = {
  board: 'Board column',
  chat: 'Chat',
  tracker: 'Task tracker',
  schedule: 'Schedule',
  webhook: 'Webhook',
  event: 'Custom event',
};

export const CHAT_PROVIDER_LABELS: Record<string, string> = {
  slack: 'Slack',
  teams: 'Microsoft Teams',
};

export function triggerSource(t: Trigger): string {
  if (t.source) return t.source;
  if (t.kind === 'column') return 'board';
  if (t.kind === 'chat') return 'chat';
  return t.kind;
}

function chatLabel(t: Trigger): string {
  return CHAT_PROVIDER_LABELS[t.chat_provider ?? ''] ?? 'Chat';
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

export function creatorLabel(t: Trigger): string {
  const name = t.created_by?.name;
  const runsAsCreator = OFF_BOARD_SOURCES.has(triggerSource(t));
  if (!name) return runsAsCreator ? 'No creator — this trigger cannot start a run' : 'Created by Unknown';
  return runsAsCreator ? `Runs as ${name}` : `Created by ${name}`;
}

// A missing creator only breaks the off-board kinds — a column trigger still runs
// under the person the card is on, so an unknown creator there is just a blank.
export function creatorTone(t: Trigger): string {
  if (t.created_by) return 'var(--text-2)';
  return OFF_BOARD_SOURCES.has(triggerSource(t)) ? 'var(--err)' : 'var(--text-3)';
}

const AIXLE_CHANGE_LABELS: Record<string, string> = {
  ignore: 'ignores Aixle changes',
  other_workflows: 'chains from other workflows',
  always: 'follows Aixle changes',
};

export function triggerMeta(
  t: Trigger,
  trackers: TrackerOption[] = [],
  chatProviders: ChatProviderOption[] = [],
): string {
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
    if (t.filter_predicate?.['conversation.type'] === 'direct') return 'direct messages';
    if (typeof channel !== 'string' || !channel) return 'anywhere the bot is addressed';
    const known = chatProviders.find((p) => p.key === t.chat_provider)?.conversations.find((c) => c.id === channel);
    return known?.name ? `in ${known.name}` : `channel ${channel}`;
  }
  const pred = t.filter_predicate ?? {};
  const keys = Object.keys(pred);
  // A custom event's type is already on its badge.
  const base = source === 'webhook' ? `verification: ${t.verification_strategy ?? 'none'}` : null;
  if (keys.length > 0) {
    const key = keys[0];
    const val = pred[key];
    const condition =
      val && typeof val === 'object'
        ? `when ${key} ${(val as { op?: string }).op ?? 'eq'} ${(val as { value?: unknown }).value}`
        : `when ${key} eq ${val}`;
    return base ? `${base} · ${condition}` : condition;
  }
  return base ?? 'any payload';
}
