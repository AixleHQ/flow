import {
  ActionIcon,
  Badge,
  Box,
  Button,
  CopyButton,
  Divider,
  Drawer,
  Group,
  Loader,
  NumberInput,
  PasswordInput,
  SegmentedControl,
  Select,
  Stack,
  Switch,
  Text,
  TextInput,
  ThemeIcon,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import {
  IconBolt,
  IconBrandSlack,
  IconCheck,
  IconColumns,
  IconCopy,
  IconPencil,
  IconPlus,
  IconTrash,
  IconWebhook,
} from '@tabler/icons-react';
import cronstrue from 'cronstrue';
import { useCallback, useEffect, useState } from 'react';

import { apiFetch } from 'shared/lib/apiFetch';
import { apiV1ProjectWorkflowTriggerPath, apiV1ProjectWorkflowTriggersPath } from 'shared/routes';

interface ColumnOption {
  id: number;
  name: string;
  boundWorkflowName?: string | null;
}

interface Trigger {
  id: number;
  kind: string;
  event_type: string;
  name?: string | null;
  trigger_mode?: string;
  cooldown_seconds?: number;
  enabled?: boolean;
  column_name?: string;
  board_column_id?: number;
  subject_policy?: string;
  subject_column_id?: number | null;
  subject_title_template?: string | null;
  filter_predicate?: Record<string, unknown>;
  schedule_config?: { cron?: string; timezone?: string };
}

interface Props {
  opened: boolean;
  onClose: () => void;
  projectId: number;
  workflowId: number;
  columns: ColumnOption[];
}

type Kind = 'column' | 'slack' | 'webhook' | 'schedule';

const KIND_META: Record<string, { label: string; color: string; icon: typeof IconBolt }> = {
  column: { label: 'Task enters column', color: 'teal', icon: IconColumns },
  slack: { label: 'Slack message', color: 'grape', icon: IconBrandSlack },
  webhook: { label: 'Inbound webhook', color: 'orange', icon: IconWebhook },
  schedule: { label: 'Schedule', color: 'green', icon: IconBolt },
  event: { label: 'Event', color: 'blue', icon: IconBolt },
};

// IANA timezone list from the runtime (falls back to UTC if unsupported).
const TIMEZONES: string[] = (() => {
  try {
    const intl = Intl as typeof Intl & { supportedValuesOf?: (key: string) => string[] };
    return intl.supportedValuesOf?.('timeZone') ?? ['UTC'];
  } catch {
    return ['UTC'];
  }
})();

// Append the current UTC offset to a timezone, e.g. "Europe/Belgrade (UTC+02:00)".
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

const TIMEZONE_OPTIONS = TIMEZONES.map((tz) => ({ value: tz, label: tzLabel(tz) }));

// Human-readable description of a cron expression (e.g. "At 09:00, Monday through Friday").
function describeCron(expr: string): { ok: boolean; text: string } {
  const value = expr.trim();
  if (!value) return { ok: false, text: 'Enter a cron expression' };
  try {
    return { ok: true, text: cronstrue.toString(value, { throwExceptionOnParseError: true, verbose: false }) };
  } catch {
    return { ok: false, text: 'Not a valid cron expression' };
  }
}

export function WorkflowTriggersDrawer({ opened, onClose, projectId, workflowId, columns }: Props) {
  const [triggers, setTriggers] = useState<Trigger[]>([]);
  const [loading, setLoading] = useState(false);
  const [adding, setAdding] = useState(false);
  const [editing, setEditing] = useState<Trigger | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await apiFetch(apiV1ProjectWorkflowTriggersPath(projectId, workflowId));
      if (res.ok) {
        const data = await res.json();
        setTriggers(data.triggers ?? []);
      }
    } finally {
      setLoading(false);
    }
  }, [projectId, workflowId]);

  useEffect(() => {
    if (opened) load();
  }, [opened, load]);

  const remove = useCallback(
    async (t: Trigger) => {
      const url = apiV1ProjectWorkflowTriggerPath(
        projectId,
        workflowId,
        t.id,
        t.kind === 'column' ? { kind: 'column' } : {},
      );
      const res = await apiFetch(url, { method: 'DELETE' });
      if (res.ok) {
        setTriggers((prev) => prev.filter((x) => x.id !== t.id || x.kind !== t.kind));
      } else {
        notifications.show({ message: 'Failed to remove trigger', color: 'red' });
      }
    },
    [projectId, workflowId],
  );

  return (
    <Drawer
      opened={opened}
      onClose={onClose}
      position="right"
      size="lg"
      title={<Text fw={600}>Triggers — how this workflow launches</Text>}
    >
      <Stack gap="md">
        <Text size="sm" c="dimmed">
          Any enabled trigger can start a run. Off-board triggers (Slack, webhook) decide what task the run is about via{' '}
          <b>subject</b>.
        </Text>

        {loading ? (
          <Group justify="center" py="lg">
            <Loader size="sm" />
          </Group>
        ) : triggers.length === 0 ? (
          <Text size="sm" c="dimmed" ta="center" py="md">
            No triggers yet.
          </Text>
        ) : (
          <Stack gap="xs">
            {triggers.map((t) => {
              const meta = KIND_META[t.kind] ?? KIND_META.event;
              const Icon = meta.icon;
              if (editing && editing.id === t.id && editing.kind === t.kind) {
                return (
                  <AddTriggerForm
                    key={`edit-${t.kind}-${t.id}`}
                    projectId={projectId}
                    workflowId={workflowId}
                    columns={columns}
                    editing={t}
                    onCancel={() => setEditing(null)}
                    onCreated={() => {
                      setEditing(null);
                      load();
                    }}
                  />
                );
              }
              return (
                <Group
                  key={`${t.kind}-${t.id}`}
                  justify="space-between"
                  wrap="nowrap"
                  p="sm"
                  style={{ border: '1px solid var(--app-border-default)', borderRadius: 8 }}
                >
                  <Group gap="sm" wrap="nowrap">
                    <ThemeIcon variant="light" color={meta.color} radius="md">
                      <Icon size={16} />
                    </ThemeIcon>
                    <Box>
                      <Group gap={6}>
                        <Text size="sm" fw={600}>
                          {meta.label}
                        </Text>
                        <Badge size="xs" variant="light" color="gray">
                          {t.event_type}
                        </Badge>
                      </Group>
                      <Text size="xs" c="dimmed">
                        {triggerSummary(t)}
                      </Text>
                    </Box>
                  </Group>
                  <Group gap={4} wrap="nowrap">
                    <ActionIcon
                      variant="subtle"
                      color="gray"
                      onClick={() => {
                        setAdding(false);
                        setEditing(t);
                      }}
                      aria-label="Edit trigger"
                    >
                      <IconPencil size={16} />
                    </ActionIcon>
                    <ActionIcon variant="subtle" color="red" onClick={() => remove(t)} aria-label="Remove trigger">
                      <IconTrash size={16} />
                    </ActionIcon>
                  </Group>
                </Group>
              );
            })}
          </Stack>
        )}

        {!editing && <Divider />}

        {editing ? null : adding ? (
          <AddTriggerForm
            projectId={projectId}
            workflowId={workflowId}
            columns={columns}
            onCancel={() => setAdding(false)}
            onCreated={() => {
              setAdding(false);
              load();
            }}
          />
        ) : (
          <Button leftSection={<IconPlus size={16} />} variant="light" onClick={() => setAdding(true)}>
            Add trigger
          </Button>
        )}
      </Stack>
    </Drawer>
  );
}

function triggerSummary(t: Trigger): string {
  if (t.kind === 'column') return `${t.column_name ?? 'column'} · ${t.trigger_mode} · cooldown ${t.cooldown_seconds}s`;
  if (t.kind === 'schedule') {
    const cfg = t.schedule_config ?? {};
    return `${cfg.cron ?? '—'} · ${cfg.timezone ?? 'UTC'} · subject: ${t.subject_policy ?? 'none'}`;
  }
  const parts: string[] = [];
  const pred = t.filter_predicate ?? {};
  Object.keys(pred).forEach((k) => parts.push(k));
  const filter = parts.length ? `only when ${parts.join(', ')}` : 'any event';
  return `${filter} · subject: ${t.subject_policy ?? 'none'}`;
}

// Builds a ready-to-run curl command for the created webhook, adapting the auth
// headers to the chosen verification strategy.
function buildWebhookCurl(url: string, secret: string | undefined, verification: string): string {
  const s = secret || '<secret>';
  if (verification === 'hmac_sha256') {
    return [
      `BODY='{"hello":"world"}'`,
      `SIG=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac '${s}' | sed 's/^.* //')`,
      `curl -X POST '${url}' \\`,
      `  -H 'Content-Type: application/json' \\`,
      `  -H "X-Hub-Signature-256: sha256=$SIG" \\`,
      `  -d "$BODY"`,
    ].join('\n');
  }
  if (verification === 'shared_token') {
    return [
      `curl -X POST '${url}' \\`,
      `  -H 'Content-Type: application/json' \\`,
      `  -H 'X-Webhook-Token: ${s}' \\`,
      `  -d '{"hello":"world"}'`,
    ].join('\n');
  }
  return [`curl -X POST '${url}' \\`, `  -H 'Content-Type: application/json' \\`, `  -d '{"hello":"world"}'`].join(
    '\n',
  );
}

interface AddProps {
  projectId: number;
  workflowId: number;
  columns: ColumnOption[];
  editing?: Trigger;
  onCancel: () => void;
  onCreated: () => void;
}

// In edit mode, recover the slack/webhook filter inputs from the stored predicate.
// slack predicate: { channel, text: { op, value } }
// webhook predicate: { [field]: value } or { [field]: { op, value } }
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

function AddTriggerForm({ projectId, workflowId, columns, editing, onCancel, onCreated }: AddProps) {
  const isEdit = Boolean(editing);
  const editPred = editing?.filter_predicate ?? {};
  const editSlack = editing?.kind === 'slack' ? slackFilterFromPredicate(editPred) : null;
  const editWebhook = editing?.kind === 'webhook' ? webhookFilterFromPredicate(editPred) : null;

  const [kind, setKind] = useState<Kind>((editing?.kind as Kind) ?? 'column');
  const [saving, setSaving] = useState(false);
  const [created, setCreated] = useState<{ url: string; secret: string } | null>(null);

  // column — default to the first column not already bound to a workflow
  const [columnId, setColumnId] = useState<string | null>(
    editing?.board_column_id?.toString() ??
      (columns.find((c) => !c.boundWorkflowName) ?? columns[0])?.id?.toString() ??
      null,
  );
  const [mode, setMode] = useState(editing?.trigger_mode ?? 'auto');
  const [cooldown, setCooldown] = useState<number | string>(editing?.cooldown_seconds ?? 5);
  const [enabled, setEnabled] = useState(editing?.enabled ?? true);
  // slack
  const [channel, setChannel] = useState(editSlack?.channel ?? '');
  const [textContains, setTextContains] = useState(editSlack?.value ?? '');
  const [textOp, setTextOp] = useState(editSlack?.op ?? 'contains');
  // webhook
  const [verification, setVerification] = useState('none');
  const [secret, setSecret] = useState('');
  const [condField, setCondField] = useState(editWebhook?.field ?? '');
  const [condOp, setCondOp] = useState(editWebhook?.op ?? 'eq');
  const [condValue, setCondValue] = useState(editWebhook?.value ?? '');
  // schedule
  const [cron, setCron] = useState(editing?.schedule_config?.cron ?? '0 9 * * 1-5');
  const [timezone, setTimezone] = useState(editing?.schedule_config?.timezone ?? 'UTC');
  // shared subject
  const [subjectPolicy, setSubjectPolicy] = useState(editing?.subject_policy ?? 'none');
  const [subjectColumnId, setSubjectColumnId] = useState<string | null>(
    editing?.subject_column_id?.toString() ?? columns[0]?.id?.toString() ?? null,
  );
  const [subjectTitleTemplate, setSubjectTitleTemplate] = useState(editing?.subject_title_template ?? '');

  const columnData = columns.map((c) => ({ value: c.id.toString(), label: c.name }));
  // For the column-enter trigger: a column already bound to a workflow is taken
  // (one binding per column), so disable it and show which workflow holds it.
  const columnBindingData = columns.map((c) => ({
    value: c.id.toString(),
    label: c.boundWorkflowName ? `${c.name} (→ ${c.boundWorkflowName})` : c.name,
    disabled: Boolean(c.boundWorkflowName),
  }));
  const cronDesc = describeCron(cron);

  const submit = useCallback(async () => {
    setSaving(true);
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
        // verification_strategy + secret are immutable (set at create time only).
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
      if (subjectPolicy === 'create_task') {
        trigger.subject_column_id = subjectColumnId;
        if (subjectTitleTemplate.trim()) trigger.subject_title_template = subjectTitleTemplate.trim();
      }
      if (isEdit) trigger.enabled = enabled;
    }

    try {
      if (isEdit && editing) {
        const url = apiV1ProjectWorkflowTriggerPath(
          projectId,
          workflowId,
          editing.id,
          kind === 'column' ? { kind: 'column' } : {},
        );
        const res = await apiFetch(url, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ trigger }),
        });
        if (!res.ok) {
          const data = await res.json().catch(() => ({}));
          notifications.show({ message: (data.errors ?? ['Failed to update trigger']).join(', '), color: 'red' });
          return;
        }
        onCreated();
        return;
      }

      const res = await apiFetch(apiV1ProjectWorkflowTriggersPath(projectId, workflowId), {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ trigger }),
      });
      if (!res.ok) {
        const data = await res.json().catch(() => ({}));
        notifications.show({ message: (data.errors ?? ['Failed to add trigger']).join(', '), color: 'red' });
        return;
      }
      const data = await res.json();
      if (kind === 'webhook' && data.webhook_url) {
        setCreated({ url: data.webhook_url, secret: data.webhook_secret ?? '' });
      } else {
        onCreated();
      }
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
    onCreated,
  ]);

  if (created) {
    const curl = buildWebhookCurl(created.url, created.secret, verification);
    return (
      <Stack gap="sm" p="sm" style={{ border: '1px solid var(--app-border-default)', borderRadius: 8 }}>
        <Text size="sm" fw={600}>
          Webhook trigger created
        </Text>
        <Text size="xs" c="dimmed">
          Point your source at this URL. It is an idempotent start API for this workflow.
        </Text>
        <CopyField label="Request URL" value={created.url} />
        {created.secret && <CopyField label="Secret" value={created.secret} />}
        <Box>
          <Group justify="space-between" mb={4}>
            <Text size="xs" fw={500}>
              Example request (
              {verification === 'none' ? 'no auth' : verification === 'hmac_sha256' ? 'HMAC SHA-256' : 'shared token'})
            </Text>
            <CopyButton value={curl}>
              {({ copied, copy }) => (
                <Button
                  size="compact-xs"
                  variant="light"
                  onClick={copy}
                  leftSection={copied ? <IconCheck size={12} /> : <IconCopy size={12} />}
                >
                  {copied ? 'Copied' : 'Copy curl'}
                </Button>
              )}
            </CopyButton>
          </Group>
          <Text
            component="pre"
            size="xs"
            ff="monospace"
            style={{
              whiteSpace: 'pre',
              overflowX: 'auto',
              background: 'var(--app-bg-subtle, rgba(0,0,0,0.05))',
              padding: 8,
              borderRadius: 6,
              margin: 0,
            }}
          >
            {curl}
          </Text>
        </Box>
        <Text size="xs" c="dimmed">
          Runs the workflow as <b>you</b> — the trigger&apos;s creator.
        </Text>
        <Button onClick={onCreated}>Done</Button>
      </Stack>
    );
  }

  return (
    <Stack gap="sm" p="sm" style={{ border: '1px solid var(--app-border-default)', borderRadius: 8 }}>
      {isEdit ? (
        <Text size="sm" fw={600}>
          Edit {(KIND_META[kind] ?? KIND_META.event).label.toLowerCase()} trigger
        </Text>
      ) : (
        <SegmentedControl
          fullWidth
          value={kind}
          onChange={(v) => setKind(v as Kind)}
          data={[
            { value: 'column', label: 'Column' },
            { value: 'schedule', label: 'Schedule' },
            { value: 'slack', label: 'Slack' },
            { value: 'webhook', label: 'Webhook' },
          ]}
        />
      )}

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
            <Box>
              <Text size="xs" fw={500} mb={4}>
                Mode
              </Text>
              <SegmentedControl
                fullWidth
                value={mode}
                onChange={setMode}
                data={[
                  { value: 'auto', label: 'Auto' },
                  { value: 'manual', label: 'Manual' },
                ]}
              />
            </Box>
            <NumberInput label="Cooldown (s)" value={cooldown} onChange={setCooldown} min={0} />
          </Group>
        </>
      )}

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
          <Text size="xs" c={cronDesc.ok ? 'teal' : 'dimmed'}>
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
          <Text size="xs" c="dimmed">
            A timer starts a workflow, not a task — unless you pick “Create a task” below.
          </Text>
          <SubjectPicker
            subjectPolicy={subjectPolicy}
            setSubjectPolicy={setSubjectPolicy}
            columnData={columnData}
            subjectColumnId={subjectColumnId}
            setSubjectColumnId={setSubjectColumnId}
            subjectTitleTemplate={subjectTitleTemplate}
            setSubjectTitleTemplate={setSubjectTitleTemplate}
          />
        </>
      )}

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
              ]}
              value={textOp}
              onChange={(v) => setTextOp(v ?? 'contains')}
              allowDeselect={false}
            />
            <TextInput
              label="Pattern"
              placeholder={textOp === 'regex' ? '^run report' : 'ship it (optional)'}
              value={textContains}
              onChange={(e) => setTextContains(e.currentTarget.value)}
            />
          </Group>
          <SubjectPicker
            subjectPolicy={subjectPolicy}
            setSubjectPolicy={setSubjectPolicy}
            columnData={columnData}
            subjectColumnId={subjectColumnId}
            setSubjectColumnId={setSubjectColumnId}
            subjectTitleTemplate={subjectTitleTemplate}
            setSubjectTitleTemplate={setSubjectTitleTemplate}
          />
        </>
      )}

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
              />
              <PasswordInput
                label="Secret"
                placeholder="optional"
                value={secret}
                onChange={(e) => setSecret(e.currentTarget.value)}
              />
            </Group>
          )}
          <Text size="xs" fw={500}>
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
            />
            <TextInput
              label="Value"
              placeholder="refs/heads/main"
              value={condValue}
              onChange={(e) => setCondValue(e.currentTarget.value)}
            />
          </Group>
          <SubjectPicker
            subjectPolicy={subjectPolicy}
            setSubjectPolicy={setSubjectPolicy}
            columnData={columnData}
            subjectColumnId={subjectColumnId}
            setSubjectColumnId={setSubjectColumnId}
            subjectTitleTemplate={subjectTitleTemplate}
            setSubjectTitleTemplate={setSubjectTitleTemplate}
          />
        </>
      )}

      {isEdit && kind !== 'column' && (
        <Switch label="Enabled" checked={enabled} onChange={(e) => setEnabled(e.currentTarget.checked)} />
      )}

      <Group justify="flex-end">
        <Button variant="default" onClick={onCancel}>
          Cancel
        </Button>
        <Button onClick={submit} loading={saving} disabled={kind === 'schedule' && !cronDesc.ok}>
          {isEdit ? 'Save' : 'Add trigger'}
        </Button>
      </Group>
    </Stack>
  );
}

function SubjectPicker({
  subjectPolicy,
  setSubjectPolicy,
  columnData,
  subjectColumnId,
  setSubjectColumnId,
  subjectTitleTemplate,
  setSubjectTitleTemplate,
}: {
  subjectPolicy: string;
  setSubjectPolicy: (v: string) => void;
  columnData: { value: string; label: string }[];
  subjectColumnId: string | null;
  setSubjectColumnId: (v: string | null) => void;
  subjectTitleTemplate: string;
  setSubjectTitleTemplate: (v: string) => void;
}) {
  return (
    <>
      <Select
        label="Subject (what the run is about)"
        data={[
          { value: 'none', label: 'None — project-level run' },
          { value: 'create_task', label: 'Create a task' },
        ]}
        value={subjectPolicy}
        onChange={(v) => setSubjectPolicy(v ?? 'none')}
      />
      {subjectPolicy === 'create_task' && (
        <>
          <Select label="Task column" data={columnData} value={subjectColumnId} onChange={setSubjectColumnId} />
          <TextInput
            label="Task title template"
            placeholder="webhook.received — {{date}}"
            description="Leave blank for a default. Use {{date}} or any top-level payload key, e.g. {{order_id}}."
            value={subjectTitleTemplate}
            onChange={(e) => setSubjectTitleTemplate(e.currentTarget.value)}
          />
          <Text size="xs" c="dimmed">
            The task body is filled with the triggering payload automatically.
          </Text>
        </>
      )}
    </>
  );
}

function CopyField({ label, value }: { label: string; value: string }) {
  return (
    <Box>
      <Text size="xs" fw={500} mb={4}>
        {label}
      </Text>
      <Group gap="xs" wrap="nowrap">
        <Text size="xs" ff="monospace" style={{ flex: 1, overflow: 'hidden', textOverflow: 'ellipsis' }}>
          {value}
        </Text>
        <CopyButton value={value}>
          {({ copied, copy }) => (
            <Button
              size="compact-xs"
              variant="light"
              onClick={copy}
              leftSection={copied ? <IconCheck size={12} /> : <IconCopy size={12} />}
            >
              {copied ? 'Copied' : 'Copy'}
            </Button>
          )}
        </CopyButton>
      </Group>
    </Box>
  );
}
