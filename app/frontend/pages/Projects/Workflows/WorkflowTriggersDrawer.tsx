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
                  <ActionIcon variant="subtle" color="red" onClick={() => remove(t)} aria-label="Remove trigger">
                    <IconTrash size={16} />
                  </ActionIcon>
                </Group>
              );
            })}
          </Stack>
        )}

        <Divider />

        {adding ? (
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
  return [
    `curl -X POST '${url}' \\`,
    `  -H 'Content-Type: application/json' \\`,
    `  -d '{"hello":"world"}'`,
  ].join('\n');
}

interface AddProps {
  projectId: number;
  workflowId: number;
  columns: ColumnOption[];
  onCancel: () => void;
  onCreated: () => void;
}

function AddTriggerForm({ projectId, workflowId, columns, onCancel, onCreated }: AddProps) {
  const [kind, setKind] = useState<Kind>('column');
  const [saving, setSaving] = useState(false);
  const [created, setCreated] = useState<{ url: string; secret: string } | null>(null);

  // column — default to the first column not already bound to a workflow
  const [columnId, setColumnId] = useState<string | null>(
    (columns.find((c) => !c.boundWorkflowName) ?? columns[0])?.id?.toString() ?? null,
  );
  const [mode, setMode] = useState('auto');
  const [cooldown, setCooldown] = useState<number | string>(5);
  // slack
  const [channel, setChannel] = useState('');
  const [textContains, setTextContains] = useState('');
  const [textOp, setTextOp] = useState('contains');
  // webhook
  const [verification, setVerification] = useState('none');
  const [secret, setSecret] = useState('');
  const [condField, setCondField] = useState('');
  const [condOp, setCondOp] = useState('eq');
  const [condValue, setCondValue] = useState('');
  // schedule
  const [cron, setCron] = useState('0 9 * * 1-5');
  const [timezone, setTimezone] = useState('UTC');
  // shared subject
  const [subjectPolicy, setSubjectPolicy] = useState('none');
  const [subjectColumnId, setSubjectColumnId] = useState<string | null>(columns[0]?.id?.toString() ?? null);
  const [subjectTitleTemplate, setSubjectTitleTemplate] = useState('');

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
    const trigger: Record<string, unknown> = { kind };
    if (kind === 'column') {
      trigger.board_column_id = columnId;
      trigger.trigger_mode = mode;
      trigger.cooldown_seconds = cooldown;
    } else {
      const filter: Record<string, unknown> = {};
      if (kind === 'slack') {
        if (channel.trim()) filter.channel = channel.trim();
        if (textContains.trim()) filter.text = { op: textOp, value: textContains.trim() };
      } else if (kind === 'webhook') {
        trigger.verification_strategy = verification;
        if (secret.trim()) trigger.secret = secret.trim();
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
    }

    try {
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
    kind,
    columnId,
    mode,
    cooldown,
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
              Example request ({verification === 'none' ? 'no auth' : verification === 'hmac_sha256' ? 'HMAC SHA-256' : 'shared token'})
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

      {kind === 'column' && (
        <>
          <Select
            label="Column"
            data={columnBindingData}
            value={columnId}
            onChange={setColumnId}
            placeholder="Pick a column"
            searchable
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

      <Group justify="flex-end">
        <Button variant="default" onClick={onCancel}>
          Cancel
        </Button>
        <Button onClick={submit} loading={saving} disabled={kind === 'schedule' && !cronDesc.ok}>
          Add trigger
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
