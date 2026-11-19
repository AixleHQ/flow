import type { AixleChanges } from './trackerTrigger';
import type { Trigger, TriggerRepository } from './types';

export type PullRequestEventType = 'pull_request.review.submitted' | 'pull_request.comment.created';

export type ReviewVerdict = 'approved' | 'changes_requested' | 'commented';

export interface PullRequestTriggerValue {
  eventType: PullRequestEventType;
  repositoryId: string | null;
  verdict: ReviewVerdict | null;
  mentionOnly: boolean;
  textContains: string;
  aixleChanges: AixleChanges;
  subjectPolicy: string;
  subjectColumnId: string | null;
  subjectTitleTemplate: string;
  // Conditions set through the API or MCP that the form has no field for; saving keeps them.
  otherConditions: Record<string, unknown>;
}

export const PULL_REQUEST_EVENT_OPTIONS: { value: PullRequestEventType; label: string }[] = [
  { value: 'pull_request.review.submitted', label: 'A review is submitted' },
  { value: 'pull_request.comment.created', label: 'A comment is added' },
];

export const VERDICT_OPTIONS: { value: ReviewVerdict; label: string }[] = [
  { value: 'changes_requested', label: 'Changes requested' },
  { value: 'approved', label: 'Approved' },
  { value: 'commented', label: 'Commented' },
];

export const PULL_REQUEST_SUBJECT_OPTIONS = [
  { value: 'find_or_create_task', label: "The pull request's task — create it the first time" },
  { value: 'existing_task', label: "The pull request's task, if it has one" },
  { value: 'create_task', label: 'A new task every time' },
  { value: 'none', label: 'None — project-level run' },
];

export const CODE_HOST_LABELS: Record<TriggerRepository['provider'], string> = {
  github: 'GitHub',
  gitlab: 'GitLab',
  bitbucket: 'Bitbucket',
  azure_devops: 'Azure DevOps',
};

export const VERDICT_FIELD = 'review.verdict';
export const MENTION_FIELD = 'comment.mentions_me';
const TEXT_FIELD = 'text';

type Operation = { op?: unknown; value?: unknown };

const asOperation = (value: unknown): Operation | null =>
  value !== null && typeof value === 'object' && !Array.isArray(value) ? (value as Operation) : null;

const isVerdict = (value: unknown): value is ReviewVerdict => VERDICT_OPTIONS.some((o) => o.value === value);

// Whether the form has a field that shows this condition exactly as stored.
function formShows(field: string, value: unknown, eventType: PullRequestEventType): boolean {
  if (field === VERDICT_FIELD) return eventType === 'pull_request.review.submitted' && isVerdict(value);
  if (field === MENTION_FIELD) return eventType === 'pull_request.comment.created' && value === true;
  if (field === TEXT_FIELD) {
    const operation = asOperation(value);
    return operation?.op === 'contains' && typeof operation.value === 'string';
  }
  return false;
}

export function pullRequestValueFromTrigger(
  trigger: Trigger | null,
  defaultColumnId: string | null,
): PullRequestTriggerValue {
  const predicate = trigger?.filter_predicate ?? {};
  const eventType = (trigger?.event_type as PullRequestEventType | undefined) ?? 'pull_request.review.submitted';
  const shows = (field: string) => formShows(field, predicate[field], eventType);
  const text = shows(TEXT_FIELD) ? asOperation(predicate[TEXT_FIELD]) : null;
  return {
    eventType,
    repositoryId: trigger?.repository_id?.toString() ?? null,
    verdict: shows(VERDICT_FIELD) ? (predicate[VERDICT_FIELD] as ReviewVerdict) : null,
    mentionOnly: trigger ? shows(MENTION_FIELD) : true,
    textContains: typeof text?.value === 'string' ? text.value : '',
    aixleChanges: (trigger?.aixle_changes as AixleChanges | undefined) ?? 'ignore',
    subjectPolicy: trigger?.subject_policy ?? (defaultColumnId ? 'find_or_create_task' : 'none'),
    subjectColumnId: trigger?.subject_column_id?.toString() ?? defaultColumnId,
    subjectTitleTemplate: trigger?.subject_title_template ?? '',
    otherConditions: Object.fromEntries(
      Object.entries(predicate).filter(([field, value]) => !formShows(field, value, eventType)),
    ),
  };
}

// The trigger fields a pull-request binding sends; the event type is fixed once created.
export function pullRequestTriggerPayload(value: PullRequestTriggerValue, isEdit: boolean): Record<string, unknown> {
  const filter: Record<string, unknown> = { ...value.otherConditions };
  if (value.eventType === 'pull_request.review.submitted' && value.verdict) filter[VERDICT_FIELD] = value.verdict;
  if (value.eventType === 'pull_request.comment.created' && value.mentionOnly) filter[MENTION_FIELD] = true;
  if (value.textContains.trim()) filter[TEXT_FIELD] = { op: 'contains', value: value.textContains.trim() };

  const payload: Record<string, unknown> = {
    repository_id: value.repositoryId,
    aixle_changes: value.aixleChanges,
    filter_predicate: filter,
    subject_policy: value.subjectPolicy,
  };
  if (!isEdit) payload.event_type = value.eventType;
  if (value.subjectPolicy !== 'none') {
    payload.subject_column_id = value.subjectColumnId;
    if (value.subjectTitleTemplate.trim()) payload.subject_title_template = value.subjectTitleTemplate.trim();
  }
  return payload;
}
