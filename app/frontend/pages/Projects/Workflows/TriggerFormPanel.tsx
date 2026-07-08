import { Box, Button, Group, NumberInput, PasswordInput, Select, Stack, Switch, Text, TextInput } from '@mantine/core';
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
      <Box
        style={{
          position: 'absolute',
          inset: 0,
          background: 'rgba(10,9,8,0.5)',
          zIndex: 10,
        }}
        onClick={onClose}
      />

      {/* Panel */}
      <Box
        style={{
          position: 'absolute',
          top: 0,
          right: 0,
          bottom: 0,
          width: 400,
          background: 'var(--bg-raised)',
          borderLeft: '1px solid var(--border)',
          zIndex: 20,
          display: 'flex',
          flexDirection: 'column',
          overflow: 'hidden',
        }}
      >
        {/* Header */}
        <Group justify="space-between" p={20} style={{ borderBottom: '1px solid var(--border)', flexShrink: 0 }}>
          <Text fw={600} size="sm" style={{ color: 'var(--text-1)' }}>
            {isEdit ? 'Edit trigger' : 'Add trigger'}
          </Text>
          <Button variant="subtle" size="compact-xs" style={{ color: 'var(--text-2)' }} onClick={onClose}>
            <IconX size={16} />
          </Button>
        </Group>

        {/* Body */}
        <Stack gap="md" p={20} style={{ flex: 1, overflowY: 'auto' }}>
          {/* Trigger type */}
          <Box>
            <Text
              size="xs"
              fw={600}
              style={{ color: 'var(--text-2)', textTransform: 'uppercase', letterSpacing: '0.08em' }}
              mb={6}
            >
              Trigger type
            </Text>
            {isEdit ? (
              <Group gap={6} align="center">
                <Text size="sm" style={{ color: 'var(--text-1)' }}>
                  {kindOptions.find((o) => o.value === kind)?.label ?? kind}
                </Text>
                <IconLock size={12} style={{ color: 'var(--text-3)' }} />
                <Text size="xs" style={{ color: 'var(--text-3)' }}>
                  Type is locked when editing
                </Text>
              </Group>
            ) : (
              <Select
                data={kindOptions}
                value={kind}
                onChange={(v) => setKind((v as Kind) ?? 'column')}
                allowDeselect={false}
              />
            )}
          </Box>

          {/* Column fields */}
          {kind === 'column' && (
            <>
              <Select
                label="Column"
                data={columnBindingData}
                value={columnId}
                onChange={setColumnId}
                placeholder="Pick a column"
                searchable
                disabled={isEdit}
              />
              <Group grow>
                <Select
                  label="Mode"
                  data={[
                    { value: 'auto', label: 'Auto' },
                    { value: 'manual', label: 'Manual' },
                  ]}
                  value={mode}
                  onChange={(v) => setMode(v ?? 'auto')}
                  allowDeselect={false}
                />
                <NumberInput label="Cooldown (s)" value={cooldown} onChange={setCooldown} min={0} />
              </Group>
            </>
          )}

          {/* Schedule fields */}
          {kind === 'schedule' && (
            <>
              <TextInput
                label="Cron"
                description="minute · hour · day-of-month · month · day-of-week"
                placeholder="0 9 * * 1-5"
                value={cron}
                onChange={(e) => setCron(e.currentTarget.value)}
                error={cron.trim() && !cronDesc.ok ? 'Invalid cron' : undefined}
              />
              <Text size="xs" style={{ color: cronDesc.ok ? 'var(--accent)' : 'var(--text-3)' }}>
                {cronDesc.ok ? `Runs: ${cronDesc.text}` : cronDesc.text}
              </Text>
              <Select
                label="Timezone"
                data={TIMEZONE_OPTIONS}
                value={timezone}
                onChange={(v) => setTimezone(v ?? 'UTC')}
                searchable
                nothingFoundMessage="No timezone"
              />
              <Select
                label="Subject"
                data={sessionOptions}
                value={subjectPolicy}
                onChange={(v) => setSubjectPolicy(v ?? 'none')}
                allowDeselect={false}
              />
              {subjectPolicy !== 'none' && (
                <>
                  <Select label="Task column" data={columnData} value={subjectColumnId} onChange={setSubjectColumnId} />
                  <TextInput
                    label="Task title template"
                    placeholder="webhook.received — {{date}}"
                    value={subjectTitleTemplate}
                    onChange={(e) => setSubjectTitleTemplate(e.currentTarget.value)}
                  />
                </>
              )}
            </>
          )}

          {/* Slack fields */}
          {kind === 'slack' && (
            <>
              <TextInput
                label="Channel id"
                placeholder="C0123ABC (blank = any)"
                value={channel}
                onChange={(e) => setChannel(e.currentTarget.value)}
              />
              <Group grow align="flex-end">
                <Select
                  label="Text match"
                  data={[
                    { value: 'contains', label: 'contains' },
                    { value: 'eq', label: 'equals' },
                    { value: 'regex', label: 'regex' },
                    { value: 'starts_with', label: 'starts with' },
                  ]}
                  value={textOp}
                  onChange={(v) => setTextOp(v ?? 'contains')}
                  allowDeselect={false}
                />
                <TextInput
                  label="Pattern"
                  placeholder="ship it (optional)"
                  value={textContains}
                  onChange={(e) => setTextContains(e.currentTarget.value)}
                />
              </Group>
              <Select
                label="Subject"
                data={sessionOptions}
                value={subjectPolicy}
                onChange={(v) => setSubjectPolicy(v ?? 'none')}
                allowDeselect={false}
              />
              {subjectPolicy !== 'none' && (
                <>
                  <Select label="Task column" data={columnData} value={subjectColumnId} onChange={setSubjectColumnId} />
                  <TextInput
                    label="Task title template"
                    placeholder="slack.message — {{date}}"
                    value={subjectTitleTemplate}
                    onChange={(e) => setSubjectTitleTemplate(e.currentTarget.value)}
                  />
                </>
              )}
            </>
          )}

          {/* Webhook fields */}
          {kind === 'webhook' && (
            <>
              {!isEdit && (
                <Group grow>
                  <Select
                    label="Verification"
                    data={[
                      { value: 'none', label: 'None' },
                      { value: 'hmac_sha256', label: 'HMAC SHA-256' },
                      { value: 'shared_token', label: 'Shared token' },
                    ]}
                    value={verification}
                    onChange={(v) => setVerification(v ?? 'none')}
                    allowDeselect={false}
                  />
                  <PasswordInput
                    label="Secret"
                    placeholder="optional"
                    value={secret}
                    onChange={(e) => setSecret(e.currentTarget.value)}
                  />
                </Group>
              )}
              <Text size="xs" fw={500} style={{ color: 'var(--text-2)' }}>
                Only when (optional)
              </Text>
              <Group grow align="flex-end">
                <TextInput
                  label="Field"
                  placeholder="ref"
                  value={condField}
                  onChange={(e) => setCondField(e.currentTarget.value)}
                />
                <Select
                  label="Op"
                  data={['eq', 'ne', 'contains', 'starts_with', 'ends_with'].map((o) => ({ value: o, label: o }))}
                  value={condOp}
                  onChange={(v) => setCondOp(v ?? 'eq')}
                  allowDeselect={false}
                />
                <TextInput
                  label="Value"
                  placeholder="refs/heads/main"
                  value={condValue}
                  onChange={(e) => setCondValue(e.currentTarget.value)}
                />
              </Group>
              <Select
                label="Subject"
                data={sessionOptions}
                value={subjectPolicy}
                onChange={(v) => setSubjectPolicy(v ?? 'none')}
                allowDeselect={false}
              />
              {subjectPolicy !== 'none' && (
                <>
                  <Select label="Task column" data={columnData} value={subjectColumnId} onChange={setSubjectColumnId} />
                  <TextInput
                    label="Task title template"
                    placeholder="webhook.received — {{date}}"
                    value={subjectTitleTemplate}
                    onChange={(e) => setSubjectTitleTemplate(e.currentTarget.value)}
                  />
                </>
              )}
            </>
          )}

          {/* Enabled toggle for edit mode (non-column) */}
          {isEdit && kind !== 'column' && (
            <Switch label="Enabled" checked={enabled} onChange={(e) => setEnabled(e.currentTarget.checked)} />
          )}

          {error && (
            <Text size="xs" style={{ color: 'var(--mantine-color-red-6)' }}>
              {error}
            </Text>
          )}
        </Stack>

        {/* Footer */}
        <Group justify="flex-end" gap="sm" p={20} style={{ borderTop: '1px solid var(--border)', flexShrink: 0 }}>
          <Button variant="subtle" style={{ color: 'var(--text-2)' }} onClick={onClose}>
            Cancel
          </Button>
          <Button
            onClick={submit}
            loading={saving}
            disabled={kind === 'schedule' && !cronDesc.ok}
            style={{ background: 'var(--accent)' }}
          >
            {isEdit ? 'Update trigger' : 'Add trigger'}
          </Button>
        </Group>
      </Box>
    </>
  );
}
