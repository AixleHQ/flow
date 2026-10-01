import { Select, Switch, TagsInput, TextInput } from '@mantine/core';
import type { ReactNode } from 'react';

import { useTrackerStatuses } from 'shared/resources/trackers/useTrackerStatuses';

import {
  AIXLE_CHANGE_OPTIONS,
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

interface Props {
  projectId: number;
  trackers: TrackerOption[];
  columns: { value: string; label: string }[];
  value: TrackerTriggerValue;
  isEdit: boolean;
  onChange: (value: TrackerTriggerValue) => void;
}

export function TrackerTriggerFields({ projectId, trackers, columns, value, isEdit, onChange }: Props) {
  const statuses = useTrackerStatuses(projectId, value.trackerId);
  const set = (changes: Partial<TrackerTriggerValue>) => onChange({ ...value, ...changes });
  const trackerData = [
    { value: '', label: 'Any tracker in this project' },
    ...trackers.map((t) => ({ value: t.id.toString(), label: `${t.name} (${t.handle})` })),
  ];

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
        <Hint>Any tracker keeps the trigger working while a project moves from one tracker to another.</Hint>
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
        <Switch
          label="Comment on the issue when a run fails"
          checked={value.notifyOnFailure}
          onChange={(e) => set({ notifyOnFailure: e.currentTarget.checked })}
        />
        <Hint>Also when a run is cancelled. Nothing is posted to a read-only tracker.</Hint>
      </div>

      <div style={{ marginBottom: 12 }}>
        <FieldLabel>Subject (what the run is about)</FieldLabel>
        <Select
          aria-label="Subject"
          data={SUBJECT_OPTIONS}
          value={value.subjectPolicy}
          onChange={(v) => set({ subjectPolicy: v ?? 'find_or_create_task' })}
          allowDeselect={false}
          styles={inputStyles}
        />
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
