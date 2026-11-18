import { Select, Switch, TextInput } from '@mantine/core';
import type { ReactNode } from 'react';

import {
  CODE_HOST_LABELS,
  PULL_REQUEST_EVENT_OPTIONS,
  PULL_REQUEST_SUBJECT_OPTIONS,
  VERDICT_OPTIONS,
  type PullRequestEventType,
  type PullRequestTriggerValue,
  type ReviewVerdict,
} from './pullRequestTrigger';
import { AIXLE_CHANGE_OPTIONS, describeCondition, type AixleChanges } from './trackerTrigger';
import type { TriggerRepository } from './types';

const inputStyles = {
  input: {
    background: 'var(--app-bg-paper)',
    border: '1px solid var(--app-border-default)',
    borderRadius: 5,
    fontSize: 13,
  },
};

function FieldLabel({ children }: { children: ReactNode }) {
  return (
    <div style={{ fontSize: 13, fontWeight: 500, color: 'var(--app-text-primary)', marginBottom: 5 }}>{children}</div>
  );
}

function Hint({ children }: { children: ReactNode }) {
  return <div style={{ fontSize: 12, color: 'var(--app-text-tertiary)', marginTop: 4 }}>{children}</div>;
}

const NEEDS_COLUMN = ['find_or_create_task', 'create_task'];

const MENTION_SUPPORT = 'Aixle recognises a mention on a GitHub App connection or a GitLab service account.';

function mentionHint(selected: TriggerRepository | undefined, listening: TriggerRepository[]): string | null {
  const unrecognized = listening.filter((r) => !r.mentionsRecognized);
  if (unrecognized.length === 0) return null;
  if (unrecognized.length === listening.length) {
    const through = selected ? "this repository's connection" : 'the connection of any repository in this project';
    return `This trigger cannot fire yet. Aixle cannot recognise a mention of itself through ${through}. ${MENTION_SUPPORT}`;
  }
  return `Mentions are not recognised in ${unrecognized.map((r) => r.fullName).join(', ')}. ${MENTION_SUPPORT}`;
}

interface Props {
  repositories: TriggerRepository[];
  columns: { value: string; label: string }[];
  value: PullRequestTriggerValue;
  isEdit: boolean;
  onChange: (value: PullRequestTriggerValue) => void;
}

export function PullRequestTriggerFields({ repositories, columns, value, isEdit, onChange }: Props) {
  const set = (changes: Partial<PullRequestTriggerValue>) => onChange({ ...value, ...changes });
  const selected = repositories.find((r) => r.id.toString() === value.repositoryId);
  const repositoryData = [
    { value: '', label: 'Any repository in this project' },
    ...repositories.map((r) => ({
      value: r.id.toString(),
      label: `${r.fullName} (${CODE_HOST_LABELS[r.provider] ?? r.provider})`,
    })),
    ...(value.repositoryId && !selected
      ? [{ value: value.repositoryId, label: `Repository #${value.repositoryId}` }]
      : []),
  ];
  const mentionBlocked = value.mentionOnly ? mentionHint(selected, selected ? [selected] : repositories) : null;
  const noBoard = columns.length === 0;
  const subjectData = PULL_REQUEST_SUBJECT_OPTIONS.map((o) => ({
    ...o,
    disabled: noBoard && NEEDS_COLUMN.includes(o.value),
  }));
  const otherConditions = Object.entries(value.otherConditions);

  return (
    <>
      <div style={{ marginBottom: 12 }}>
        <FieldLabel>Repository</FieldLabel>
        <Select
          aria-label="Repository"
          data={repositoryData}
          value={value.repositoryId ?? ''}
          onChange={(v) => set({ repositoryId: v || null })}
          allowDeselect={false}
          searchable
          styles={inputStyles}
        />
        <Hint>Any repository also covers the ones added to this project later.</Hint>
      </div>

      <div style={{ marginBottom: 12 }}>
        <FieldLabel>When</FieldLabel>
        {isEdit ? (
          <div style={{ fontSize: 13, color: 'var(--app-text-primary)' }}>
            {PULL_REQUEST_EVENT_OPTIONS.find((o) => o.value === value.eventType)?.label ?? value.eventType}
          </div>
        ) : (
          <Select
            aria-label="When"
            data={PULL_REQUEST_EVENT_OPTIONS}
            value={value.eventType}
            onChange={(v) => set({ eventType: (v as PullRequestEventType) ?? value.eventType })}
            allowDeselect={false}
            styles={inputStyles}
          />
        )}
      </div>

      {value.eventType === 'pull_request.review.submitted' && (
        <div style={{ marginBottom: 12 }}>
          <FieldLabel>Verdict</FieldLabel>
          <Select
            aria-label="Verdict"
            data={[{ value: '', label: 'Any verdict' }, ...VERDICT_OPTIONS]}
            value={value.verdict ?? ''}
            onChange={(v) => set({ verdict: (v as ReviewVerdict) || null })}
            allowDeselect={false}
            styles={inputStyles}
          />
        </div>
      )}

      {value.eventType === 'pull_request.comment.created' && (
        <div style={{ marginBottom: 12 }}>
          <Switch
            label="Only when Aixle is mentioned"
            checked={value.mentionOnly}
            onChange={(e) => set({ mentionOnly: e.currentTarget.checked })}
          />
          {mentionBlocked && <Hint>{mentionBlocked}</Hint>}
        </div>
      )}

      <div style={{ marginBottom: 12 }}>
        <FieldLabel>Text contains</FieldLabel>
        <TextInput
          aria-label="Text contains"
          placeholder="optional — the review or the comment"
          value={value.textContains}
          onChange={(e) => set({ textContains: e.currentTarget.value })}
          styles={inputStyles}
        />
      </div>

      {otherConditions.length > 0 && (
        <div style={{ marginBottom: 12 }}>
          <FieldLabel>Other conditions</FieldLabel>
          {otherConditions.map(([field, condition]) => (
            <div
              key={field}
              style={{ fontSize: 12, fontFamily: 'var(--app-font-mono)', color: 'var(--app-text-secondary)' }}
            >
              {describeCondition(field, condition)}
            </div>
          ))}
          <Hint>Set through the API or MCP. The form has no field for them, and saving keeps them.</Hint>
        </div>
      )}

      <div style={{ marginBottom: 12 }}>
        <FieldLabel>Changes made by Aixle</FieldLabel>
        <Select
          aria-label="Changes made by Aixle"
          data={AIXLE_CHANGE_OPTIONS}
          value={value.aixleChanges}
          onChange={(v) => set({ aixleChanges: (v as AixleChanges) ?? 'ignore' })}
          allowDeselect={false}
          styles={inputStyles}
        />
        <Hint>
          Reviews and comments Aixle wrote. “Only from other workflows” lets one workflow hand a pull request to the
          next without ever starting itself again.
        </Hint>
      </div>

      <div style={{ marginBottom: 12 }}>
        <FieldLabel>Subject (what the run is about)</FieldLabel>
        <Select
          aria-label="Subject"
          data={subjectData}
          value={value.subjectPolicy}
          onChange={(v) => set({ subjectPolicy: v ?? 'find_or_create_task' })}
          allowDeselect={false}
          styles={inputStyles}
        />
        <Hint>
          {noBoard
            ? 'This project has no board, so a run cannot get a new task.'
            : "The pull request's task is the task linked to the pull request, or the task whose run opened it."}
        </Hint>
      </div>

      {value.subjectPolicy !== 'none' && (
        <>
          <div style={{ marginBottom: 12 }}>
            <FieldLabel>Task column</FieldLabel>
            <Select
              aria-label="Task column"
              data={columns}
              value={value.subjectColumnId}
              onChange={(v) => set({ subjectColumnId: v })}
              allowDeselect={false}
              styles={inputStyles}
            />
          </div>
          <div style={{ marginBottom: 12 }}>
            <FieldLabel>Task title template</FieldLabel>
            <TextInput
              aria-label="Task title template"
              placeholder="PR {{pull_request.number}}: {{pull_request.title}}"
              value={value.subjectTitleTemplate}
              onChange={(e) => set({ subjectTitleTemplate: e.currentTarget.value })}
              styles={inputStyles}
            />
          </div>
        </>
      )}
    </>
  );
}
