import { Select, Switch, TagsInput, TextInput } from '@mantine/core';
import type { ReactNode } from 'react';

import { mentionBlocker } from 'shared/resources/trackers/mentions';
import { useTrackerStatuses } from 'shared/resources/trackers/useTrackerStatuses';

import {
  AIXLE_CHANGE_OPTIONS,
  describeCondition,
  isAttached,
  SUBJECT_OPTIONS,
  TRACKER_EVENT_OPTIONS,
  type AixleChanges,
  type TrackerEventType,
  type TrackerOption,
  type TrackerTriggerValue,
} from './trackerTrigger';

const inputStyles = {
  input: { background: 'var(--bg-card)', border: '1px solid var(--border)', borderRadius: 5, fontSize: 13 },
};

function FieldLabel({ children }: { children: ReactNode }) {
  return <div style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-1)', marginBottom: 5 }}>{children}</div>;
}

function Hint({ children }: { children: ReactNode }) {
  return <div style={{ fontSize: 12, color: 'var(--text-3)', marginTop: 4 }}>{children}</div>;
}

const NEEDS_COLUMN = ['find_or_create_task', 'create_task'];

interface Props {
  projectId: number;
  trackers: TrackerOption[];
  columns: { value: string; label: string }[];
  value: TrackerTriggerValue;
  isEdit: boolean;
  onChange: (value: TrackerTriggerValue) => void;
}

export function TrackerTriggerFields({ projectId, trackers, columns, value, isEdit, onChange }: Props) {
  const { statuses } = useTrackerStatuses(projectId, value.trackerId);
  const set = (changes: Partial<TrackerTriggerValue>) => onChange({ ...value, ...changes });
  const selected = trackers.find((t) => t.id.toString() === value.trackerId);
  const trackerData = [
    { value: '', label: 'Any tracker in this project' },
    ...trackers
      .filter((t) => isAttached(t) || t === selected)
      .map((t) => ({
        value: t.id.toString(),
        label: `${t.name} (${t.handle})${isAttached(t) ? '' : ' — detached'}`,
      })),
  ];
  const listening = selected ? [selected] : trackers.filter(isAttached);
  const mentionsBlocked = listening.flatMap((t) => {
    const reason = mentionBlocker(t);
    return reason ? [{ tracker: t, reason }] : [];
  });
  const noBoard = columns.length === 0;
  const subjectData = SUBJECT_OPTIONS.map((o) => ({ ...o, disabled: noBoard && NEEDS_COLUMN.includes(o.value) }));
  const otherConditions = Object.entries(value.otherConditions);

  return (
    <>
      <div style={{ marginBottom: 12 }}>
        <FieldLabel>Tracker</FieldLabel>
        <Select
          aria-label="Tracker"
          data={trackerData}
          value={value.trackerId ?? ''}
          onChange={(v) => set({ trackerId: v || null })}
          allowDeselect={false}
          styles={inputStyles}
        />
        <Hint>
          {selected && !isAttached(selected)
            ? 'This tracker is detached, so the trigger does not fire. It fires again once the tracker is attached again on the Trackers page.'
            : 'Any tracker keeps the trigger working while a project moves from one tracker to another.'}
        </Hint>
      </div>

      <div style={{ marginBottom: 12 }}>
        <FieldLabel>When</FieldLabel>
        {isEdit ? (
          <div style={{ fontSize: 13, color: 'var(--text-1)' }}>
            {TRACKER_EVENT_OPTIONS.find((o) => o.value === value.eventType)?.label ?? value.eventType}
          </div>
        ) : (
          <Select
            aria-label="When"
            data={TRACKER_EVENT_OPTIONS}
            value={value.eventType}
            onChange={(v) => set({ eventType: (v as TrackerEventType) ?? value.eventType })}
            allowDeselect={false}
            styles={inputStyles}
          />
        )}
      </div>

      {value.eventType === 'tracker.issue.status_changed' && (
        <div style={{ marginBottom: 12 }}>
          <FieldLabel>Moves to</FieldLabel>
          <TagsInput
            aria-label="Moves to"
            placeholder={value.statuses.length ? '' : 'Ready for AI (blank = any status)'}
            data={statuses}
            value={value.statuses}
            onChange={(v) => set({ statuses: v })}
            styles={inputStyles}
          />
          <Hint>A column on the tracker&apos;s board. Adding one column for Aixle is enough to start.</Hint>
        </div>
      )}

      {value.eventType === 'tracker.comment.created' && (
        <div style={{ marginBottom: 12 }}>
          <Switch
            label="Only when Aixle is mentioned"
            checked={value.mentionOnly}
            onChange={(e) => set({ mentionOnly: e.currentTarget.checked })}
          />
          {value.mentionOnly &&
            mentionsBlocked.map(({ tracker, reason }) => (
              <Hint key={tracker.id}>
                {listening.length > 1 ? `${tracker.name}: ` : 'This trigger cannot fire yet. '}
                {reason}
              </Hint>
            ))}
        </div>
      )}

      <div style={{ marginBottom: 12 }}>
        <FieldLabel>Text contains</FieldLabel>
        <TextInput
          aria-label="Text contains"
          placeholder="optional — title and description, or the comment"
          value={value.textContains}
          onChange={(e) => set({ textContains: e.currentTarget.value })}
          styles={inputStyles}
        />
      </div>

      {otherConditions.length > 0 && (
        <div style={{ marginBottom: 12 }}>
          <FieldLabel>Other conditions</FieldLabel>
          {otherConditions.map(([field, condition]) => (
            <div key={field} style={{ fontSize: 12, fontFamily: 'monospace', color: 'var(--text-2)' }}>
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
          “Only from other workflows” lets one workflow hand an issue to the next without ever starting itself again.
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
        {noBoard && <Hint>This project has no board, so a run cannot get a new task.</Hint>}
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
              placeholder="{{issue.key}} {{issue.title}}"
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
