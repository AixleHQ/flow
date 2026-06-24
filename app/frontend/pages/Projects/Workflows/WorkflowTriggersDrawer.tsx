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
import { useCallback, useEffect, useState } from 'react';

import { apiFetch } from 'shared/lib/apiFetch';
import { apiV1ProjectWorkflowTriggerPath, apiV1ProjectWorkflowTriggersPath } from 'shared/routes';

interface ColumnOption {
  id: number;
  name: string;
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

  // column
  const [columnId, setColumnId] = useState<string | null>(columns[0]?.id?.toString() ?? null);
  const [mode, setMode] = useState('auto');
  const [cooldown, setCooldown] = useState<number | string>(5);
  // slack
  const [channel, setChannel] = useState('');
  const [textContains, setTextContains] = useState('');
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

  const columnData = columns.map((c) => ({ value: c.id.toString(), label: c.name }));

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
        if (textContains.trim()) filter.text = { op: 'contains', value: textContains.trim() };
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
      if (subjectPolicy === 'create_task') trigger.subject_column_id = subjectColumnId;
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
    verification,
    secret,
    condField,
    condOp,
    condValue,
    cron,
    timezone,
    subjectPolicy,
    subjectColumnId,
    projectId,
    workflowId,
    onCreated,
  ]);

  if (created) {
    return (
      <Stack gap="sm" p="sm" style={{ border: '1px solid var(--app-border-default)', borderRadius: 8 }}>
        <Text size="sm" fw={600}>
          Webhook trigger created
        </Text>
        <Text size="xs" c="dimmed">
          Point your source at this URL. It is a signed, idempotent start API for this workflow.
        </Text>
        <CopyField label="Request URL" value={created.url} />
        {created.secret && <CopyField label="Secret" value={created.secret} />}
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
            data={columnData}
            value={columnId}
            onChange={setColumnId}
            placeholder="Pick a column"
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
            placeholder="0 9 * * 1-5"
            value={cron}
            onChange={(e) => setCron(e.currentTarget.value)}
          />
          <TextInput
            label="Timezone"
            placeholder="UTC"
            value={timezone}
            onChange={(e) => setTimezone(e.currentTarget.value)}
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
          <TextInput
            label="Text contains"
            placeholder="ship it (optional)"
            value={textContains}
            onChange={(e) => setTextContains(e.currentTarget.value)}
          />
          <SubjectPicker
            subjectPolicy={subjectPolicy}
            setSubjectPolicy={setSubjectPolicy}
            columnData={columnData}
            subjectColumnId={subjectColumnId}
            setSubjectColumnId={setSubjectColumnId}
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
          />
        </>
      )}

      <Group justify="flex-end">
        <Button variant="default" onClick={onCancel}>
          Cancel
        </Button>
        <Button onClick={submit} loading={saving}>
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
}: {
  subjectPolicy: string;
  setSubjectPolicy: (v: string) => void;
  columnData: { value: string; label: string }[];
  subjectColumnId: string | null;
  setSubjectColumnId: (v: string | null) => void;
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
        <Select label="Task column" data={columnData} value={subjectColumnId} onChange={setSubjectColumnId} />
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
