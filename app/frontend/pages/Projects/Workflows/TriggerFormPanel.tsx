import { NumberInput, PasswordInput, Select, Switch, TextInput } from '@mantine/core';
import { IconLock, IconX } from '@tabler/icons-react';
import cronstrue from 'cronstrue';
import { useCallback, useState } from 'react';

import { apiFetch } from 'shared/lib/apiFetch';
import { apiV1ProjectWorkflowTriggerPath, apiV1ProjectWorkflowTriggersPath } from 'shared/routes';

import type { Trigger } from './TriggersTab';

interface ColumnOption {
  id: number;
  name: string;
  boundWorkflowName?: string | null;
}

interface StepOption {
  id: number;
  name: string;
}

interface TriggerFormPanelProps {
  projectId: number;
  workflowId: number;
  columns: ColumnOption[];
  sessions: StepOption[];
  editing: Trigger | null;
  defaultKind: string;
  onClose: () => void;
  onSaved: () => void;
}

type Kind = 'column' | 'slack' | 'webhook' | 'schedule';

const IANA_TIMEZONES: string[] = (() => {
  try {
    const intl = Intl as typeof Intl & { supportedValuesOf?: (key: string) => string[] };
    return intl.supportedValuesOf?.('timeZone') ?? ['UTC'];
  } catch {
    return ['UTC'];
  }
})();

function tzLabel(tz: string): string {
  try {
    const raw =
      new Intl.DateTimeFormat('en-US', { timeZone: tz, timeZoneName: 'longOffset' })
        .formatToParts(new Date())
        .find((p) => p.type === 'timeZoneName')?.value ?? 'GMT';
    const offset = raw === 'GMT' ? 'UTC+00:00' : raw.replace('GMT', 'UTC');
    return `${tz} (${offset})`;
  } catch {
    return tz;
  }
}

const TIMEZONE_OPTIONS = IANA_TIMEZONES.map((tz) => ({ value: tz, label: tzLabel(tz) }));

function describeCron(expr: string): { ok: boolean; text: string } {
  const value = expr.trim();
  if (!value) return { ok: false, text: 'Enter a cron expression' };
  try {
    return { ok: true, text: cronstrue.toString(value, { throwExceptionOnParseError: true, verbose: false }) };
  } catch {
    return { ok: false, text: 'Not a valid cron expression' };
  }
}

function slackFilterFromPredicate(pred: Record<string, unknown>): { channel: string; op: string; value: string } {
  const channel = typeof pred.channel === 'string' ? pred.channel : '';
  const text = pred.text;
  if (text && typeof text === 'object') {
    const t = text as { op?: string; value?: string };
    return { channel, op: t.op ?? 'contains', value: t.value ?? '' };
  }
  if (typeof text === 'string') return { channel, op: 'contains', value: text };
  return { channel, op: 'contains', value: '' };
}

function webhookFilterFromPredicate(pred: Record<string, unknown>): { field: string; op: string; value: string } {
  const field = Object.keys(pred)[0];
  if (!field) return { field: '', op: 'eq', value: '' };
  const raw = pred[field];
  if (raw && typeof raw === 'object') {
    const r = raw as { op?: string; value?: unknown };
    return { field, op: r.op ?? 'eq', value: r.value == null ? '' : String(r.value) };
  }
  return { field, op: 'eq', value: raw == null ? '' : String(raw) };
}

export function TriggerFormPanel({
  projectId,
  workflowId,
  columns,
  sessions,
  editing,
  defaultKind,
  onClose,
  onSaved,
}: TriggerFormPanelProps) {
  const isEdit = Boolean(editing);
  const editPred = editing?.filter_predicate ?? {};
  const editSlack = editing?.kind === 'slack' ? slackFilterFromPredicate(editPred) : null;
  const editWebhook = editing?.kind === 'webhook' ? webhookFilterFromPredicate(editPred) : null;

  const [kind, setKind] = useState<Kind>((editing?.kind as Kind) ?? (defaultKind as Kind));
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [columnId, setColumnId] = useState<string | null>(
    editing?.board_column_id?.toString() ??
      (columns.find((c) => !c.boundWorkflowName) ?? columns[0])?.id?.toString() ??
      null,
  );
  const [mode, setMode] = useState(editing?.trigger_mode ?? 'auto');
  const [cooldown, setCooldown] = useState<number | string>(editing?.cooldown_seconds ?? 5);
  const [enabled, setEnabled] = useState(editing?.enabled ?? true);

  const [channel, setChannel] = useState(editSlack?.channel ?? '');
  const [textContains, setTextContains] = useState(editSlack?.value ?? '');
  const [textOp, setTextOp] = useState(editSlack?.op ?? 'contains');

  const [verification, setVerification] = useState('none');
  const [secret, setSecret] = useState('');
  const [condField, setCondField] = useState(editWebhook?.field ?? '');
  const [condOp, setCondOp] = useState(editWebhook?.op ?? 'eq');
  const [condValue, setCondValue] = useState(editWebhook?.value ?? '');

  const [cron, setCron] = useState(editing?.schedule_config?.cron ?? '0 9 * * 1-5');
  const [timezone, setTimezone] = useState(editing?.schedule_config?.timezone ?? 'UTC');

  const [subjectPolicy, setSubjectPolicy] = useState(editing?.subject_policy ?? 'none');
  const [subjectColumnId, setSubjectColumnId] = useState<string | null>(
    editing?.subject_column_id?.toString() ?? columns[0]?.id?.toString() ?? null,
  );
  const [subjectTitleTemplate, setSubjectTitleTemplate] = useState(editing?.subject_title_template ?? '');

  const columnData = columns.map((c) => ({ value: c.id.toString(), label: c.name }));
  const columnBindingData = columns.map((c) => ({
    value: c.id.toString(),
    label: c.boundWorkflowName ? `${c.name} (→ ${c.boundWorkflowName})` : c.name,
    disabled: Boolean(c.boundWorkflowName),
  }));
  const sessionOptions = [
    { value: 'none', label: 'None — project-level run' },
    ...sessions.map((s) => ({ value: String(s.id), label: `Create a task · ${s.name}` })),
  ];
  const cronDesc = describeCron(cron);

  const submit = useCallback(async () => {
    setSaving(true);
    setError(null);
    const trigger: Record<string, unknown> = isEdit ? {} : { kind };

    if (kind === 'column') {
      if (!isEdit) trigger.board_column_id = columnId;
      trigger.trigger_mode = mode;
      trigger.cooldown_seconds = cooldown;
    } else {
      const filter: Record<string, unknown> = {};
      if (kind === 'slack') {
        if (channel.trim()) filter.channel = channel.trim();
        if (textContains.trim()) filter.text = { op: textOp, value: textContains.trim() };
      } else if (kind === 'webhook') {
        if (!isEdit) {
          trigger.verification_strategy = verification;
          if (secret.trim()) trigger.secret = secret.trim();
        }
        if (condField.trim()) {
          filter[condField.trim()] = condOp === 'eq' ? condValue : { op: condOp, value: condValue };
        }
      } else if (kind === 'schedule') {
        trigger.schedule_config = { cron: cron.trim(), timezone: timezone.trim() || 'UTC' };
      }
      trigger.filter_predicate = filter;
      trigger.subject_policy = subjectPolicy;
      if (subjectPolicy !== 'none') {
        trigger.subject_column_id = subjectColumnId;
        if (subjectTitleTemplate.trim()) trigger.subject_title_template = subjectTitleTemplate.trim();
      }
      if (isEdit) trigger.enabled = enabled;
    }

    try {
      let res: Response;
      if (isEdit && editing) {
        const url = apiV1ProjectWorkflowTriggerPath(
          projectId,
          workflowId,
          editing.id,
          kind === 'column' ? { kind: 'column' } : {},
        );
        res = await apiFetch(url, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ trigger }),
        });
      } else {
        res = await apiFetch(apiV1ProjectWorkflowTriggersPath(projectId, workflowId), {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ trigger }),
        });
      }
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        setError((data.errors ?? ['Failed to save trigger']).join(', '));
        return;
      }
      onSaved();
    } finally {
      setSaving(false);
    }
  }, [
    isEdit,
    editing,
    kind,
    columnId,
    mode,
    cooldown,
    enabled,
    channel,
    textContains,
    textOp,
    verification,
    secret,
    condField,
    condOp,
    condValue,
    cron,
    timezone,
    subjectPolicy,
    subjectColumnId,
    subjectTitleTemplate,
    projectId,
    workflowId,
    onSaved,
  ]);

  const kindOptions = [
    { value: 'column', label: 'Task enters column' },
    { value: 'schedule', label: 'On schedule' },
    { value: 'slack', label: 'Slack message' },
    { value: 'webhook', label: 'Incoming webhook' },
  ];

  return (
    <>
      {/* Scrim */}
      <div
        style={{
          position: 'fixed',
          inset: 0,
          background: 'rgba(0,0,0,0.45)',
          zIndex: 90,
        }}
        onClick={onClose}
      />

      {/* Panel */}
      <div
        style={{
          position: 'fixed',
          top: 0,
          right: 0,
          bottom: 0,
          width: 480,
          maxWidth: '92vw',
          background: 'var(--bg-card)',
          borderLeft: '1px solid var(--border)',
          zIndex: 91,
          display: 'flex',
          flexDirection: 'column',
          overflow: 'hidden',
        }}
      >
        {/* Header */}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            padding: '16px 24px',
            borderBottom: '1px solid var(--border)',
            flexShrink: 0,
          }}
        >
          <div style={{ fontSize: 16, fontWeight: 600, color: 'var(--text-1)' }}>
            {isEdit ? 'Edit trigger' : 'Add trigger'}
          </div>
          <button
            onClick={onClose}
            title="Close"
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
            <IconX size={16} />
          </button>
        </div>

        {/* Body */}
        <div style={{ flex: 1, overflowY: 'auto', padding: 24 }}>
          {/* Trigger type */}
          <div style={{ marginBottom: 16 }}>
            <label style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-1)', display: 'block', marginBottom: 5 }}>
              Trigger type
            </label>
            {isEdit ? (
              <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <span style={{ fontSize: 13, color: 'var(--text-1)' }}>
                  {kindOptions.find((o) => o.value === kind)?.label ?? kind}
                </span>
                <IconLock size={12} style={{ color: 'var(--text-3)' }} />
                <span style={{ fontSize: 12, color: 'var(--text-3)' }}>Type is locked when editing</span>
              </div>
            ) : (
              <Select
                data={kindOptions}
                value={kind}
                onChange={(v) => setKind((v as Kind) ?? 'column')}
                allowDeselect={false}
                styles={{
                  input: {
                    background: 'var(--bg-card)',
                    border: '1px solid var(--border)',
                    borderRadius: 5,
                    fontSize: 13,
                  },
                }}
              />
            )}
          </div>

          {/* Column fields */}
          {kind === 'column' && (
            <>
              <div style={{ marginBottom: 12 }}>
                <label
                  style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-1)', display: 'block', marginBottom: 5 }}
                >
                  Column
                </label>
                <Select
                  data={columnBindingData}
                  value={columnId}
                  onChange={setColumnId}
                  placeholder="Pick a column"
                  searchable
                  disabled={isEdit}
                  styles={{
                    input: {
                      background: 'var(--bg-card)',
                      border: '1px solid var(--border)',
                      borderRadius: 5,
                      fontSize: 13,
                    },
                  }}
                />
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginTop: 16 }}>
                <div>
                  <label
                    style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-1)', display: 'block', marginBottom: 6 }}
                  >
                    Mode
                  </label>
                  <div
                    style={{
                      display: 'inline-flex',
                      background: 'var(--bg-raised)',
                      border: '1px solid var(--border)',
                      borderRadius: 8,
                      padding: 3,
                      gap: 2,
                    }}
                  >
                    {['auto', 'manual'].map((m) => (
                      <button
                        key={m}
                        onClick={() => setMode(m)}
                        style={{
                          padding: '6px 20px',
                          fontSize: 12,
                          fontWeight: 500,
                          color: mode === m ? 'var(--text-1)' : 'var(--text-2)',
                          background: mode === m ? 'var(--bg-card)' : 'transparent',
                          borderRadius: 4,
                          border: 'none',
                          cursor: 'pointer',
                          transition: 'all 0.12s',
                          fontFamily: 'inherit',
                          textTransform: 'capitalize',
                        }}
                      >
                        {m.charAt(0).toUpperCase() + m.slice(1)}
                      </button>
                    ))}
                  </div>
                </div>
                <div>
                  <label
                    style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-1)', display: 'block', marginBottom: 5 }}
                  >
                    Cooldown (s)
                  </label>
                  <NumberInput
                    value={cooldown}
                    onChange={setCooldown}
                    min={0}
                    styles={{
                      input: {
                        background: 'var(--bg-card)',
                        border: '1px solid var(--border)',
                        borderRadius: 5,
                        fontSize: 13,
                      },
                    }}
                  />
                </div>
              </div>
            </>
          )}

          {/* Schedule fields */}
          {kind === 'schedule' && (
            <>
              <div style={{ marginBottom: 12 }}>
                <label
                  style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-1)', display: 'block', marginBottom: 5 }}
                >
                  Cron
                </label>
                <div style={{ fontSize: 12, color: 'var(--text-2)', marginBottom: 6, lineHeight: 1.5 }}>
                  minute · hour · day-of-month · month · day-of-week
                </div>
                <TextInput
                  placeholder="0 9 * * 1-5"
                  value={cron}
                  onChange={(e) => setCron(e.currentTarget.value)}
                  error={cron.trim() && !cronDesc.ok ? 'Invalid cron' : undefined}
                  styles={{
                    input: {
                      background: 'var(--bg-card)',
                      border: '1px solid var(--border)',
                      borderRadius: 5,
                      fontSize: 13,
                    },
                  }}
                />
                <div style={{ fontSize: 12, color: cronDesc.ok ? 'var(--accent)' : 'var(--text-3)', marginTop: 6 }}>
                  {cronDesc.ok ? `Runs: ${cronDesc.text}` : cronDesc.text}
                </div>
              </div>
              <div style={{ marginBottom: 12 }}>
                <label
                  style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-1)', display: 'block', marginBottom: 5 }}
                >
                  Timezone
                </label>
                <Select
                  data={TIMEZONE_OPTIONS}
                  value={timezone}
                  onChange={(v) => setTimezone(v ?? 'UTC')}
                  searchable
                  nothingFoundMessage="No timezone"
                  styles={{
                    input: {
                      background: 'var(--bg-card)',
                      border: '1px solid var(--border)',
                      borderRadius: 5,
                      fontSize: 13,
                    },
                  }}
                />
              </div>
              <div style={{ marginBottom: 12 }}>
                <label
                  style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-1)', display: 'block', marginBottom: 5 }}
                >
                  Subject (what the run is about)
                </label>
                <Select
                  data={sessionOptions}
                  value={subjectPolicy}
                  onChange={(v) => setSubjectPolicy(v ?? 'none')}
                  allowDeselect={false}
                  styles={{
                    input: {
                      background: 'var(--bg-card)',
                      border: '1px solid var(--border)',
                      borderRadius: 5,
                      fontSize: 13,
                    },
                  }}
                />
              </div>
              {subjectPolicy !== 'none' && (
                <>
                  <div style={{ marginBottom: 12 }}>
                    <label
                      style={{
                        fontSize: 13,
                        fontWeight: 500,
                        color: 'var(--text-1)',
                        display: 'block',
                        marginBottom: 5,
                      }}
                    >
                      Task column
                    </label>
                    <Select
                      data={columnData}
                      value={subjectColumnId}
                      onChange={setSubjectColumnId}
                      styles={{
                        input: {
                          background: 'var(--bg-card)',
                          border: '1px solid var(--border)',
                          borderRadius: 5,
                          fontSize: 13,
                        },
                      }}
                    />
                  </div>
                  <div style={{ marginBottom: 12 }}>
                    <label
                      style={{
                        fontSize: 13,
                        fontWeight: 500,
                        color: 'var(--text-1)',
                        display: 'block',
                        marginBottom: 5,
                      }}
                    >
                      Task title template
                    </label>
                    <TextInput
                      placeholder="webhook.received — {{date}}"
                      value={subjectTitleTemplate}
                      onChange={(e) => setSubjectTitleTemplate(e.currentTarget.value)}
                      styles={{
                        input: {
                          background: 'var(--bg-card)',
                          border: '1px solid var(--border)',
                          borderRadius: 5,
                          fontSize: 13,
                        },
                      }}
                    />
                  </div>
                </>
              )}
            </>
          )}

          {/* Slack fields */}
          {kind === 'slack' && (
            <>
              <div style={{ marginBottom: 12 }}>
                <label
                  style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-1)', display: 'block', marginBottom: 5 }}
                >
                  Channel id
                </label>
                <TextInput
                  placeholder="C0123ABC (blank = any)"
                  value={channel}
                  onChange={(e) => setChannel(e.currentTarget.value)}
                  styles={{
                    input: {
                      background: 'var(--bg-card)',
                      border: '1px solid var(--border)',
                      borderRadius: 5,
                      fontSize: 13,
                    },
                  }}
                />
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: '150px 1fr', gap: 12, marginBottom: 12 }}>
                <div>
                  <label
                    style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-1)', display: 'block', marginBottom: 5 }}
                  >
                    Text match
                  </label>
                  <Select
                    data={[
                      { value: 'contains', label: 'contains' },
                      { value: 'eq', label: 'equals' },
                      { value: 'regex', label: 'regex' },
                      { value: 'starts_with', label: 'starts with' },
                    ]}
                    value={textOp}
                    onChange={(v) => setTextOp(v ?? 'contains')}
                    allowDeselect={false}
                    styles={{
                      input: {
                        background: 'var(--bg-card)',
                        border: '1px solid var(--border)',
                        borderRadius: 5,
                        fontSize: 13,
                      },
                    }}
                  />
                </div>
                <div>
                  <label
                    style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-1)', display: 'block', marginBottom: 5 }}
                  >
                    Pattern
                  </label>
                  <TextInput
                    placeholder="ship it (optional)"
                    value={textContains}
                    onChange={(e) => setTextContains(e.currentTarget.value)}
                    styles={{
                      input: {
                        background: 'var(--bg-card)',
                        border: '1px solid var(--border)',
                        borderRadius: 5,
                        fontSize: 13,
                      },
                    }}
                  />
                </div>
              </div>
              <div style={{ marginBottom: 12 }}>
                <label
                  style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-1)', display: 'block', marginBottom: 5 }}
                >
                  Subject (what the run is about)
                </label>
                <Select
                  data={sessionOptions}
                  value={subjectPolicy}
                  onChange={(v) => setSubjectPolicy(v ?? 'none')}
                  allowDeselect={false}
                  styles={{
                    input: {
                      background: 'var(--bg-card)',
                      border: '1px solid var(--border)',
                      borderRadius: 5,
                      fontSize: 13,
                    },
                  }}
                />
              </div>
              {subjectPolicy !== 'none' && (
                <>
                  <div style={{ marginBottom: 12 }}>
                    <label
                      style={{
                        fontSize: 13,
                        fontWeight: 500,
                        color: 'var(--text-1)',
                        display: 'block',
                        marginBottom: 5,
                      }}
                    >
                      Task column
                    </label>
                    <Select
                      data={columnData}
                      value={subjectColumnId}
                      onChange={setSubjectColumnId}
                      styles={{
                        input: {
                          background: 'var(--bg-card)',
                          border: '1px solid var(--border)',
                          borderRadius: 5,
                          fontSize: 13,
                        },
                      }}
                    />
                  </div>
                  <div style={{ marginBottom: 12 }}>
                    <label
                      style={{
                        fontSize: 13,
                        fontWeight: 500,
                        color: 'var(--text-1)',
                        display: 'block',
                        marginBottom: 5,
                      }}
                    >
                      Task title template
                    </label>
                    <TextInput
                      placeholder="slack.message — {{date}}"
                      value={subjectTitleTemplate}
                      onChange={(e) => setSubjectTitleTemplate(e.currentTarget.value)}
                      styles={{
                        input: {
                          background: 'var(--bg-card)',
                          border: '1px solid var(--border)',
                          borderRadius: 5,
                          fontSize: 13,
                        },
                      }}
                    />
                  </div>
                </>
              )}
            </>
          )}

          {/* Webhook fields */}
          {kind === 'webhook' && (
            <>
              {!isEdit && (
                <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginBottom: 12 }}>
                  <div>
                    <label
                      style={{
                        fontSize: 13,
                        fontWeight: 500,
                        color: 'var(--text-1)',
                        display: 'block',
                        marginBottom: 5,
                      }}
                    >
                      Verification
                    </label>
                    <Select
                      data={[
                        { value: 'none', label: 'None' },
                        { value: 'hmac_sha256', label: 'HMAC SHA-256' },
                        { value: 'shared_token', label: 'Shared token' },
                      ]}
                      value={verification}
                      onChange={(v) => setVerification(v ?? 'none')}
                      allowDeselect={false}
                      styles={{
                        input: {
                          background: 'var(--bg-card)',
                          border: '1px solid var(--border)',
                          borderRadius: 5,
                          fontSize: 13,
                        },
                      }}
                    />
                  </div>
                  <div>
                    <label
                      style={{
                        fontSize: 13,
                        fontWeight: 500,
                        color: 'var(--text-1)',
                        display: 'block',
                        marginBottom: 5,
                      }}
                    >
                      Secret
                    </label>
                    <PasswordInput
                      placeholder="optional"
                      value={secret}
                      onChange={(e) => setSecret(e.currentTarget.value)}
                      styles={{
                        input: {
                          background: 'var(--bg-card)',
                          border: '1px solid var(--border)',
                          borderRadius: 5,
                          fontSize: 13,
                        },
                      }}
                    />
                  </div>
                </div>
              )}
              <div style={{ fontSize: 12, fontWeight: 500, color: 'var(--text-2)', marginBottom: 8 }}>
                Only when (optional)
              </div>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 90px 1fr', gap: 10, marginBottom: 12 }}>
                <div>
                  <label
                    style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-1)', display: 'block', marginBottom: 5 }}
                  >
                    Field
                  </label>
                  <TextInput
                    placeholder="ref"
                    value={condField}
                    onChange={(e) => setCondField(e.currentTarget.value)}
                    styles={{
                      input: {
                        background: 'var(--bg-card)',
                        border: '1px solid var(--border)',
                        borderRadius: 5,
                        fontSize: 13,
                      },
                    }}
                  />
                </div>
                <div>
                  <label
                    style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-1)', display: 'block', marginBottom: 5 }}
                  >
                    Op
                  </label>
                  <Select
                    data={['eq', 'ne', 'contains', 'starts_with', 'ends_with'].map((o) => ({ value: o, label: o }))}
                    value={condOp}
                    onChange={(v) => setCondOp(v ?? 'eq')}
                    allowDeselect={false}
                    styles={{
                      input: {
                        background: 'var(--bg-card)',
                        border: '1px solid var(--border)',
                        borderRadius: 5,
                        fontSize: 13,
                      },
                    }}
                  />
                </div>
                <div>
                  <label
                    style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-1)', display: 'block', marginBottom: 5 }}
                  >
                    Value
                  </label>
                  <TextInput
                    placeholder="refs/heads/main"
                    value={condValue}
                    onChange={(e) => setCondValue(e.currentTarget.value)}
                    styles={{
                      input: {
                        background: 'var(--bg-card)',
                        border: '1px solid var(--border)',
                        borderRadius: 5,
                        fontSize: 13,
                      },
                    }}
                  />
                </div>
              </div>
              <div style={{ marginBottom: 12 }}>
                <label
                  style={{ fontSize: 13, fontWeight: 500, color: 'var(--text-1)', display: 'block', marginBottom: 5 }}
                >
                  Subject (what the run is about)
                </label>
                <Select
                  data={sessionOptions}
                  value={subjectPolicy}
                  onChange={(v) => setSubjectPolicy(v ?? 'none')}
                  allowDeselect={false}
                  styles={{
                    input: {
                      background: 'var(--bg-card)',
                      border: '1px solid var(--border)',
                      borderRadius: 5,
                      fontSize: 13,
                    },
                  }}
                />
              </div>
              {subjectPolicy !== 'none' && (
                <>
                  <div style={{ marginBottom: 12 }}>
                    <label
                      style={{
                        fontSize: 13,
                        fontWeight: 500,
                        color: 'var(--text-1)',
                        display: 'block',
                        marginBottom: 5,
                      }}
                    >
                      Task column
                    </label>
                    <Select
                      data={columnData}
                      value={subjectColumnId}
                      onChange={setSubjectColumnId}
                      styles={{
                        input: {
                          background: 'var(--bg-card)',
                          border: '1px solid var(--border)',
                          borderRadius: 5,
                          fontSize: 13,
                        },
                      }}
                    />
                  </div>
                  <div style={{ marginBottom: 12 }}>
                    <label
                      style={{
                        fontSize: 13,
                        fontWeight: 500,
                        color: 'var(--text-1)',
                        display: 'block',
                        marginBottom: 5,
                      }}
                    >
                      Task title template
                    </label>
                    <TextInput
                      placeholder="webhook.received — {{date}}"
                      value={subjectTitleTemplate}
                      onChange={(e) => setSubjectTitleTemplate(e.currentTarget.value)}
                      styles={{
                        input: {
                          background: 'var(--bg-card)',
                          border: '1px solid var(--border)',
                          borderRadius: 5,
                          fontSize: 13,
                        },
                      }}
                    />
                  </div>
                </>
              )}
            </>
          )}

          {/* Enabled toggle for edit mode (non-column) */}
          {isEdit && kind !== 'column' && (
            <Switch label="Enabled" checked={enabled} onChange={(e) => setEnabled(e.currentTarget.checked)} />
          )}

          {error && <div style={{ fontSize: 12, color: 'var(--mantine-color-red-6)', marginTop: 8 }}>{error}</div>}
        </div>

        {/* Footer */}
        <div
          style={{
            display: 'flex',
            justifyContent: 'flex-end',
            gap: 10,
            padding: '16px 24px',
            borderTop: '1px solid var(--border)',
            flexShrink: 0,
          }}
        >
          <button
            onClick={onClose}
            style={{
              background: 'none',
              border: '1px solid var(--border)',
              borderRadius: 6,
              padding: '8px 16px',
              fontSize: 13,
              fontWeight: 500,
              color: 'var(--text-2)',
              cursor: 'pointer',
              fontFamily: 'inherit',
              transition: 'all 0.12s',
            }}
            onMouseEnter={(e) => {
              (e.currentTarget as HTMLElement).style.color = 'var(--text-1)';
              (e.currentTarget as HTMLElement).style.background = 'var(--bg-hover)';
            }}
            onMouseLeave={(e) => {
              (e.currentTarget as HTMLElement).style.color = 'var(--text-2)';
              (e.currentTarget as HTMLElement).style.background = 'none';
            }}
          >
            Cancel
          </button>
          <button
            onClick={submit}
            disabled={saving || (kind === 'schedule' && !cronDesc.ok)}
            style={{
              background: saving || (kind === 'schedule' && !cronDesc.ok) ? 'var(--accent-dim)' : 'var(--accent)',
              border: 'none',
              borderRadius: 6,
              padding: '8px 16px',
              fontSize: 13,
              fontWeight: 600,
              color: saving || (kind === 'schedule' && !cronDesc.ok) ? 'var(--accent-muted)' : '#fff',
              cursor: saving || (kind === 'schedule' && !cronDesc.ok) ? 'not-allowed' : 'pointer',
              fontFamily: 'inherit',
              transition: 'all 0.12s',
            }}
          >
            {saving ? 'Saving…' : isEdit ? 'Update trigger' : 'Add trigger'}
          </button>
        </div>
      </div>
    </>
  );
}
