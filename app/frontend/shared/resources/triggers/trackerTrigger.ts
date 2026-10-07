import type { Trigger } from './types';

export interface TrackerOption {
  id: number;
  handle: string;
  name: string;
  provider: string;
  status?: string;
  mentionsRecognized?: boolean;
}

export const isAttached = (tracker: TrackerOption) => tracker.status !== 'detached';

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
  notifyOnFailure: boolean;
  subjectPolicy: string;
  subjectColumnId: string | null;
  subjectTitleTemplate: string;
  // Conditions set through the API or MCP that the form has no field for; saving keeps them.
  otherConditions: Record<string, unknown>;
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
const TEXT_FIELD = 'text';

type Operation = { op?: unknown; value?: unknown };

const asOperation = (value: unknown): Operation | null =>
  value !== null && typeof value === 'object' && !Array.isArray(value) ? (value as Operation) : null;

// Whether the form has a field that shows this condition exactly as stored.
function formShows(field: string, value: unknown, eventType: TrackerEventType): boolean {
  const operation = asOperation(value);
  if (field === STATUS_FIELD)
    return eventType === 'tracker.issue.status_changed' && operation?.op === 'in' && Array.isArray(operation.value);
  if (field === MENTION_FIELD) return eventType === 'tracker.comment.created' && value === true;
  if (field === TEXT_FIELD) return operation?.op === 'contains' && typeof operation.value === 'string';
  return false;
}

export function trackerValueFromTrigger(trigger: Trigger | null, defaultColumnId: string | null): TrackerTriggerValue {
  const predicate = trigger?.filter_predicate ?? {};
  const eventType = (trigger?.event_type as TrackerEventType | undefined) ?? 'tracker.issue.status_changed';
  const shown = (field: string) =>
    formShows(field, predicate[field], eventType) ? asOperation(predicate[field]) : null;
  const status = shown(STATUS_FIELD);
  const text = shown(TEXT_FIELD);
  return {
    eventType,
    trackerId: trigger?.project_tracker_id?.toString() ?? null,
    statuses: Array.isArray(status?.value) ? status.value.map(String) : [],
    mentionOnly: trigger ? formShows(MENTION_FIELD, predicate[MENTION_FIELD], eventType) : true,
    textContains: typeof text?.value === 'string' ? text.value : '',
    notifyOnFailure: trigger ? trigger.status_reporting !== 'none' : true,
    aixleChanges: (trigger?.aixle_changes as AixleChanges | undefined) ?? 'ignore',
    subjectPolicy: trigger?.subject_policy ?? (defaultColumnId ? 'find_or_create_task' : 'none'),
    subjectColumnId: trigger?.subject_column_id?.toString() ?? defaultColumnId,
    subjectTitleTemplate: trigger?.subject_title_template ?? '',
    otherConditions: Object.fromEntries(
      Object.entries(predicate).filter(([field, value]) => !formShows(field, value, eventType)),
    ),
  };
}

export function describeCondition(field: string, value: unknown): string {
  const operation = asOperation(value);
  if (operation && 'op' in operation) return `${field} ${String(operation.op)} ${JSON.stringify(operation.value)}`;
  return `${field} = ${JSON.stringify(value)}`;
}

// The trigger fields a tracker binding sends; the event type is fixed once created.
export function trackerTriggerPayload(value: TrackerTriggerValue, isEdit: boolean): Record<string, unknown> {
  const filter: Record<string, unknown> = { ...value.otherConditions };
  if (value.eventType === 'tracker.issue.status_changed' && value.statuses.length > 0) {
    filter[STATUS_FIELD] = { op: 'in', value: value.statuses };
  }
  if (value.eventType === 'tracker.comment.created' && value.mentionOnly) filter[MENTION_FIELD] = true;
  if (value.textContains.trim()) filter[TEXT_FIELD] = { op: 'contains', value: value.textContains.trim() };

  const payload: Record<string, unknown> = {
    project_tracker_id: value.trackerId,
    aixle_changes: value.aixleChanges,
    filter_predicate: filter,
    subject_policy: value.subjectPolicy,
    status_reporting: value.notifyOnFailure ? 'failures' : 'none',
  };
  if (!isEdit) payload.event_type = value.eventType;
  if (value.subjectPolicy !== 'none') {
    payload.subject_column_id = value.subjectColumnId;
    if (value.subjectTitleTemplate.trim()) payload.subject_title_template = value.subjectTitleTemplate.trim();
  }
  return payload;
}
