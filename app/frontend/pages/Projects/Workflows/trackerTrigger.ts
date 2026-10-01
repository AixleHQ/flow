import type { Trigger } from './types';

export interface TrackerOption {
  id: number;
  handle: string;
  name: string;
  provider: string;
}

export type TrackerEventType =
  'tracker.issue.created' | 'tracker.issue.status_changed' | 'tracker.issue.assigned' | 'tracker.comment.created';

export type AixleChanges = 'ignore' | 'other_workflows' | 'always';

export interface TrackerTriggerValue {
  eventType: TrackerEventType;
  trackerId: string | null;
  statuses: string[];
  mentionOnly: boolean;
  textContains: string;
  aixleChanges: AixleChanges;
  subjectPolicy: string;
  subjectColumnId: string | null;
  subjectTitleTemplate: string;
  notifyOnFailure: boolean;
}

export const TRACKER_EVENT_OPTIONS: { value: TrackerEventType; label: string }[] = [
  { value: 'tracker.issue.status_changed', label: 'Issue moves to a status (column)' },
  { value: 'tracker.issue.created', label: 'Issue is created' },
  { value: 'tracker.issue.assigned', label: 'Issue is assigned' },
  { value: 'tracker.comment.created', label: 'Comment is added' },
];

export const AIXLE_CHANGE_OPTIONS: { value: AixleChanges; label: string }[] = [
  { value: 'ignore', label: 'Ignore them' },
  { value: 'other_workflows', label: 'Only from other workflows' },
  { value: 'always', label: 'Always (up to the chain limits)' },
];

export const SUBJECT_OPTIONS = [
  { value: 'find_or_create_task', label: "The issue's task — create it the first time" },
  { value: 'existing_task', label: "The issue's task, if it has one" },
  { value: 'create_task', label: 'A new task every time' },
  { value: 'none', label: 'None — project-level run' },
];

const STATUS_FIELD = 'change.to.name';
const MENTION_FIELD = 'comment.mentions_me';

export function trackerValueFromTrigger(trigger: Trigger | null, defaultColumnId: string | null): TrackerTriggerValue {
  const predicate = trigger?.filter_predicate ?? {};
  const status = predicate[STATUS_FIELD] as { value?: unknown } | undefined;
  const text = predicate.text as { value?: unknown } | undefined;
  return {
    eventType: (trigger?.event_type as TrackerEventType | undefined) ?? 'tracker.issue.status_changed',
    trackerId: trigger?.project_tracker_id?.toString() ?? null,
    statuses: Array.isArray(status?.value) ? status.value.map(String) : [],
    mentionOnly: trigger ? predicate[MENTION_FIELD] === true : true,
    textContains: typeof text?.value === 'string' ? text.value : '',
    aixleChanges: (trigger?.aixle_changes as AixleChanges | undefined) ?? 'ignore',
    subjectPolicy: trigger?.subject_policy ?? 'find_or_create_task',
    subjectColumnId: trigger?.subject_column_id?.toString() ?? defaultColumnId,
    subjectTitleTemplate: trigger?.subject_title_template ?? '',
    notifyOnFailure: trigger?.notify_on_failure ?? true,
  };
}

// The trigger fields a tracker binding sends; the event type is fixed once created.
export function trackerTriggerPayload(value: TrackerTriggerValue, isEdit: boolean): Record<string, unknown> {
  const filter: Record<string, unknown> = {};
  if (value.eventType === 'tracker.issue.status_changed' && value.statuses.length > 0) {
    filter[STATUS_FIELD] = { op: 'in', value: value.statuses };
  }
  if (value.eventType === 'tracker.comment.created' && value.mentionOnly) filter[MENTION_FIELD] = true;
  if (value.textContains.trim()) filter.text = { op: 'contains', value: value.textContains.trim() };

  const payload: Record<string, unknown> = {
    project_tracker_id: value.trackerId,
    aixle_changes: value.aixleChanges,
    filter_predicate: filter,
    subject_policy: value.subjectPolicy,
    notify_on_failure: value.notifyOnFailure,
  };
  if (!isEdit) payload.event_type = value.eventType;
  if (value.subjectPolicy !== 'none') {
    payload.subject_column_id = value.subjectColumnId;
    if (value.subjectTitleTemplate.trim()) payload.subject_title_template = value.subjectTitleTemplate.trim();
  }
  return payload;
}
