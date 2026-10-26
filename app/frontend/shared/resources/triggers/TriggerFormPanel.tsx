import { usePage } from '@inertiajs/react';
import {
  Button,
  type ComboboxData,
  type ComboboxItem,
  CopyButton,
  NumberInput,
  PasswordInput,
  SegmentedControl,
  Select,
  Switch,
  TextInput,
} from '@mantine/core';
import { IconCheck, IconCopy, IconLock, IconPlus, IconUser, IconX } from '@tabler/icons-react';
import cronstrue from 'cronstrue';
import { useCallback, useState } from 'react';

import { apiFetch } from 'shared/lib/apiFetch';
import { TIMEZONE_OPTIONS } from 'shared/lib/timezones';
import { ConnectChannelModal } from 'shared/resources/chat-channels/ConnectChannelModal';
import type { ChatChannel } from 'shared/resources/chat-channels/types';
import { apiV1ProjectWorkflowTriggerPath, apiV1ProjectWorkflowTriggersPath } from 'shared/routes';
import type { SharedProps } from 'shared/ui';

import { CHAT_PROVIDER_LABELS } from './describeTrigger';
import {
  isAttached,
  trackerTriggerPayload,
  trackerValueFromTrigger,
  type TrackerOption,
  type TrackerTriggerValue,
} from './trackerTrigger';
import { TrackerTriggerFields } from './TrackerTriggerFields';
import type {
  ChatConversationOption,
  ChatProviderOption,
  Trigger,
  TriggerColumnOption,
  TriggerWorkflowOption,
} from './types';

interface TriggerFormPanelProps {
  projectId: number;
  // The workflow the trigger belongs to. Without one (the project's Triggers
  // page), a new trigger's workflow is picked in the form.
  workflowId?: number;
  workflows?: TriggerWorkflowOption[];
  columns: TriggerColumnOption[];
  trackers?: TrackerOption[];
  // Messengers the company has connected, with the channels connected to the company in each.
  chatProviders?: ChatProviderOption[];
  editing: Trigger | null;
  defaultKind: string;
  onClose: () => void;
  onSaved: () => void;
}

type Kind = 'column' | 'chat' | 'webhook' | 'schedule' | 'tracker';

// Off-board triggers fire unattended: the run belongs to whoever added the
// trigger and uses their credentials. A column trigger's run belongs to the
// person the card puts on it, so its creator is provenance, not identity.
const OFF_BOARD_KINDS: Kind[] = ['chat', 'webhook', 'schedule', 'tracker'];

function describeCron(expr: string): { ok: boolean; text: string } {
  const value = expr.trim();
  if (!value) return { ok: false, text: 'Enter a cron expression' };
  try {
    return { ok: true, text: cronstrue.toString(value, { throwExceptionOnParseError: true, verbose: false }) };
  } catch {
    return { ok: false, text: 'Not a valid cron expression' };
  }
}

function chatFilterFromPredicate(pred: Record<string, unknown>): { op: string; value: string } {
  const text = pred.text;
  if (text && typeof text === 'object') {
    const t = text as { op?: string; value?: string };
    return { op: t.op ?? 'contains', value: t.value ?? '' };
  }
  if (typeof text === 'string') return { op: 'contains', value: text };
  return { op: 'contains', value: '' };
}

// The server refuses a condition on where a message came from — the trigger's channel says that
// (TriggerBinding::CHAT_ROUTING_KEYS) — so carrying one over would fail the save.
const CHAT_PLACE_KEYS = ['channel', 'conversation', 'workspace', 'team', 'integration_id', 'subject', 'service_url'];

// Conditions set through the API or MCP that the form has no field for, such as the sender.
function chatConditionsKept(pred: Record<string, unknown>): Record<string, unknown> {
  return Object.fromEntries(
    Object.entries(pred).filter(
      ([key]) =>
        key !== 'provider' &&
        key !== 'text' &&
        !CHAT_PLACE_KEYS.some((root) => key === root || key.startsWith(`${root}.`)),
    ),
  );
}

const conversationOption = (channel: ChatChannel): ChatConversationOption => ({
  id: channel.id,
  name: channel.name,
  label: channel.label,
  kind: channel.kind,
  teamName: channel.team_name,
  provider: channel.provider,
});

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
  workflowId: fixedWorkflowId,
  workflows = [],
  columns,
  trackers = [],
  chatProviders = [],
  editing,
  defaultKind,
  onClose,
  onSaved,
}: TriggerFormPanelProps) {
  const { currentUser } = usePage<SharedProps>().props;
  const isEdit = Boolean(editing);
  const editPred = editing?.filter_predicate ?? {};
  const editChat = editing && editing.kind === 'chat' ? chatFilterFromPredicate(editPred) : null;
  const editWebhook = editing?.kind === 'webhook' ? webhookFilterFromPredicate(editPred) : null;

  const [kind, setKind] = useState<Kind>((editing?.kind ?? defaultKind) as Kind);
  const [pickedWorkflowId, setPickedWorkflowId] = useState<string | null>(
    editing?.workflow_id?.toString() ?? (workflows.length === 1 ? workflows[0].id.toString() : null),
  );
  const workflowId = fixedWorkflowId ?? editing?.workflow_id ?? (pickedWorkflowId ? Number(pickedWorkflowId) : null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // Set after a webhook is created: keeps the panel open on a success view showing
  // the request URL, secret, and a ready-to-run example cURL.
  const [created, setCreated] = useState<{ url: string; secret: string; verification: string } | null>(null);

  const [columnId, setColumnId] = useState<string | null>(
    editing?.board_column_id?.toString() ??
      (columns.find((c) => !c.boundWorkflowName) ?? columns[0])?.id?.toString() ??
      null,
  );
  const [mode, setMode] = useState(editing?.trigger_mode ?? 'auto');
  const [cooldown, setCooldown] = useState<number | string>(editing?.cooldown_seconds ?? 5);
  const [enabled, setEnabled] = useState(editing?.enabled ?? true);

  const [chatProvider, setChatProvider] = useState(editing?.chat_provider ?? chatProviders[0]?.key ?? 'slack');
  const [chatChannelId, setChatChannelId] = useState<number | null>(editing?.chat_channel?.id ?? null);
  // Channels connected from this form, and the edited trigger's own: the page's list predates both.
  const [extraChannels, setExtraChannels] = useState<ChatConversationOption[]>(() =>
    editing?.chat_channel ? [conversationOption(editing.chat_channel)] : [],
  );
  const [submitted, setSubmitted] = useState(false);
  const [statusReporting, setStatusReporting] = useState(editing?.status_reporting ?? 'lifecycle');
  const [textContains, setTextContains] = useState(editChat?.value ?? '');
  const [textOp, setTextOp] = useState(editChat?.op ?? 'contains');
  const [chatCooldown, setChatCooldown] = useState<number | string>(editChat ? (editing?.cooldown_seconds ?? 0) : 0);

  const [verification, setVerification] = useState('shared_token');
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
  const [trackerValue, setTrackerValue] = useState<TrackerTriggerValue>(() =>
    trackerValueFromTrigger(editing?.kind === 'tracker' ? editing : null, columns[0]?.id?.toString() ?? null),
  );

  const columnData = columns.map((c) => ({ value: c.id.toString(), label: c.name }));
  const columnBindingData = columns.map((c) => ({
    value: c.id.toString(),
    label: c.boundWorkflowName ? `${c.name} (→ ${c.boundWorkflowName})` : c.name,
    disabled: Boolean(c.boundWorkflowName),
  }));
  const sessionOptions = [
    { value: 'none', label: 'None — project-level run' },
    { value: 'create_task', label: 'Create a task' },
  ];
  const cronDesc = describeCron(cron);
  // A new trigger starts switched on, and a chat trigger is only on with a channel.
  const channelMissing = kind === 'chat' && chatChannelId === null && (!isEdit || enabled);

  const channelConnected = (channel: ChatChannel) => {
    setExtraChannels((prev) => [...prev.filter((c) => c.id !== channel.id), conversationOption(channel)]);
    if (channel.provider === chatProvider) setChatChannelId(channel.id);
  };

  const submit = useCallback(async () => {
    if (!workflowId) {
      setError('Choose the workflow this trigger starts');
      return;
    }
    setSubmitted(true);
    if (channelMissing) return;
    setSaving(true);
    setError(null);
    const trigger: Record<string, unknown> = isEdit ? {} : { kind };

    if (kind === 'column') {
      if (!isEdit) trigger.board_column_id = columnId;
      trigger.trigger_mode = mode;
      trigger.cooldown_seconds = cooldown;
    } else if (kind === 'tracker') {
      Object.assign(trigger, trackerTriggerPayload(trackerValue, isEdit));
      if (isEdit) trigger.enabled = enabled;
    } else {
      const filter: Record<string, unknown> = {};
      if (kind === 'chat') {
        Object.assign(filter, chatConditionsKept(editing?.filter_predicate ?? {}));
        filter.provider = chatProvider;
        if (textContains.trim()) filter.text = { op: textOp, value: textContains.trim() };
        if (!isEdit) trigger.chat_provider = chatProvider;
        trigger.chat_channel_id = chatChannelId;
        trigger.status_reporting = statusReporting;
        trigger.cooldown_seconds = chatCooldown === '' ? 0 : chatCooldown;
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
      if (!isEdit && kind === 'webhook') {
        const data = await res.json().catch(() => ({}));
        if (data.webhook_url) {
          setCreated({
            url: data.webhook_url,
            secret: data.webhook_secret ?? '',
            verification: data.verification_strategy ?? verification,
          });
          return;
        }
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
    chatProvider,
    chatChannelId,
    channelMissing,
    statusReporting,
    textContains,
    textOp,
    chatCooldown,
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
    trackerValue,
    projectId,
    workflowId,
    onSaved,
  ]);

  // Once a webhook has been created the trigger already exists on the server, so
  // explicitly dismissing the panel via ✕ or Done must still refresh the list.
  const dismiss = created ? onSaved : onClose;

  const runsAsCreator = OFF_BOARD_KINDS.includes(kind);
  // On create the trigger is recorded as the signed-in user; on edit it keeps
  // the creator it was given (the creator is not reassignable in v1).
  const creatorName = isEdit ? (editing?.created_by?.name ?? null) : (currentUser?.name ?? null);
  // A missing creator only blocks the off-board kinds; on a column trigger it is
  // just an unknown, so it is not flagged red.
  const creatorTone = creatorName ? null : runsAsCreator ? 'var(--app-danger-fg)' : 'var(--app-text-tertiary)';
  const creatorHint = creatorName
    ? runsAsCreator
      ? 'Unattended runs from this trigger belong to this user and use their credentials.'
      : 'Recorded when the trigger was added. The run itself belongs to whoever the card is on.'
    : runsAsCreator
      ? 'Without a creator this trigger cannot start a run. Re-create it to record one.'
      : 'This trigger was added before creators were recorded.';

  const kindOptions = [
    { value: 'column', label: 'Task enters column' },
    { value: 'schedule', label: 'On schedule' },
    { value: 'chat', label: 'Chat message' },
    { value: 'webhook', label: 'Incoming webhook' },
    ...(trackers.some(isAttached) || kind === 'tracker' ? [{ value: 'tracker', label: 'Task tracker event' }] : []),
  ];

  return (
    <>
      {/* Scrim */}
      <div
        data-testid="trigger-form-scrim"
        style={{
          position: 'fixed',
          inset: 0,
          background: 'rgba(0,0,0,0.45)',
          zIndex: 90,
        }}
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
          background: 'var(--app-bg-paper)',
          borderLeft: '1px solid var(--app-border-default)',
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
            borderBottom: '1px solid var(--app-border-default)',
            flexShrink: 0,
          }}
        >
          <div style={{ fontSize: 16, fontWeight: 600, color: 'var(--app-text-primary)' }}>
            {isEdit ? 'Edit trigger' : 'Add trigger'}
          </div>
          <button
            onClick={dismiss}
            title="Close"
            style={{
              background: 'none',
              border: 'none',
              cursor: 'pointer',
              color: 'var(--app-text-tertiary)',
              padding: 6,
              borderRadius: 4,
              display: 'flex',
              transition: 'all 0.12s',
            }}
            onMouseEnter={(e) => {
              (e.currentTarget as HTMLElement).style.color = 'var(--app-text-primary)';
              (e.currentTarget as HTMLElement).style.background = 'var(--app-bg-hover)';
            }}
            onMouseLeave={(e) => {
              (e.currentTarget as HTMLElement).style.color = 'var(--app-text-tertiary)';
              (e.currentTarget as HTMLElement).style.background = 'none';
            }}
          >
            <IconX size={16} />
          </button>
        </div>

        {created ? (
          <WebhookCreatedView created={created} onDone={onSaved} />
        ) : (
          <>
            {/* Body */}
            <div style={{ flex: 1, overflowY: 'auto', padding: 24 }}>
              {fixedWorkflowId === undefined && (
                <div style={{ marginBottom: 16 }}>
                  {isEdit ? (
                    <>
                      <label
                        style={{
                          fontSize: 13,
                          fontWeight: 500,
                          color: 'var(--app-text-primary)',
                          display: 'block',
                          marginBottom: 5,
                        }}
                      >
                        Workflow
                      </label>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                        <span style={{ fontSize: 13, color: 'var(--app-text-primary)' }}>
                          {editing?.workflow_name ?? 'Unknown workflow'}
                        </span>
                        <IconLock size={12} style={{ color: 'var(--app-text-tertiary)' }} />
                      </div>
                    </>
                  ) : (
                    <Select
                      label="Workflow"
                      placeholder="The workflow this trigger starts"
                      data={workflows.map((w) => ({ value: w.id.toString(), label: w.name }))}
                      value={pickedWorkflowId}
                      onChange={setPickedWorkflowId}
                      searchable
                      allowDeselect={false}
                    />
                  )}
                </div>
              )}

              {/* Trigger type */}
              <div style={{ marginBottom: 16 }}>
                <label
                  style={{
                    fontSize: 13,
                    fontWeight: 500,
                    color: 'var(--app-text-primary)',
                    display: 'block',
                    marginBottom: 5,
                  }}
                >
                  Trigger type
                </label>
                {isEdit ? (
                  <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                    <span style={{ fontSize: 13, color: 'var(--app-text-primary)' }}>
                      {kindOptions.find((o) => o.value === kind)?.label ?? kind}
                    </span>
                    <IconLock size={12} style={{ color: 'var(--app-text-tertiary)' }} />
                    <span style={{ fontSize: 12, color: 'var(--app-text-tertiary)' }}>Type is locked when editing</span>
                  </div>
                ) : (
                  <Select
                    data={kindOptions}
                    value={kind}
                    onChange={(v) => setKind((v as Kind) ?? 'column')}
                    allowDeselect={false}
                    styles={{
                      input: {
                        background: 'var(--app-bg-paper)',
                        border: '1px solid var(--app-border-default)',
                        borderRadius: 5,
                        fontSize: 13,
                      },
                    }}
                  />
                )}
              </div>

              {/* Creator — recorded on create, never editable */}
              <div style={{ marginBottom: 16 }}>
                <label
                  style={{
                    fontSize: 13,
                    fontWeight: 500,
                    color: 'var(--app-text-primary)',
                    display: 'block',
                    marginBottom: 5,
                  }}
                >
                  {runsAsCreator ? 'Runs as' : 'Created by'}
                </label>
                <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                  <IconUser size={13} style={{ color: creatorTone ?? 'var(--app-text-tertiary)' }} />
                  <span style={{ fontSize: 13, color: creatorTone ?? 'var(--app-text-primary)' }}>
                    {creatorName ?? 'Unknown'}
                  </span>
                  <IconLock size={12} style={{ color: 'var(--app-text-tertiary)' }} />
                </div>
                <div style={{ fontSize: 12, color: 'var(--app-text-tertiary)', marginTop: 4 }}>{creatorHint}</div>
              </div>

              {/* Column fields */}
              {kind === 'column' && (
                <>
                  <div style={{ marginBottom: 12 }}>
                    <label
                      style={{
                        fontSize: 13,
                        fontWeight: 500,
                        color: 'var(--app-text-primary)',
                        display: 'block',
                        marginBottom: 5,
                      }}
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
                          background: 'var(--app-bg-paper)',
                          border: '1px solid var(--app-border-default)',
                          borderRadius: 5,
                          fontSize: 13,
                        },
                      }}
                    />
                  </div>
                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginTop: 16 }}>
                    <div>
                      <label
                        style={{
                          fontSize: 13,
                          fontWeight: 500,
                          color: 'var(--app-text-primary)',
                          display: 'block',
                          marginBottom: 6,
                        }}
                      >
                        Mode
                      </label>
                      <SegmentedControl
                        aria-label="Mode"
                        value={mode}
                        onChange={setMode}
                        data={[
                          { value: 'auto', label: 'Auto' },
                          { value: 'manual', label: 'Manual' },
                        ]}
                      />
                    </div>
                    <div>
                      <label
                        style={{
                          fontSize: 13,
                          fontWeight: 500,
                          color: 'var(--app-text-primary)',
                          display: 'block',
                          marginBottom: 5,
                        }}
                      >
                        Cooldown (s)
                      </label>
                      <NumberInput
                        value={cooldown}
                        onChange={setCooldown}
                        min={0}
                        styles={{
                          input: {
                            background: 'var(--app-bg-paper)',
                            border: '1px solid var(--app-border-default)',
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
                      style={{
                        fontSize: 13,
                        fontWeight: 500,
                        color: 'var(--app-text-primary)',
                        display: 'block',
                        marginBottom: 5,
                      }}
                    >
                      Cron
                    </label>
                    <div style={{ fontSize: 12, color: 'var(--app-text-secondary)', marginBottom: 6, lineHeight: 1.5 }}>
                      minute · hour · day-of-month · month · day-of-week
                    </div>
                    <TextInput
                      placeholder="0 9 * * 1-5"
                      value={cron}
                      onChange={(e) => setCron(e.currentTarget.value)}
                      error={cron.trim() && !cronDesc.ok ? 'Invalid cron' : undefined}
                      styles={{
                        input: {
                          background: 'var(--app-bg-paper)',
                          border: '1px solid var(--app-border-default)',
                          borderRadius: 5,
                          fontSize: 13,
                        },
                      }}
                    />
                    <div
                      style={{
                        fontSize: 12,
                        color: cronDesc.ok ? 'var(--mantine-color-green-6)' : 'var(--app-text-tertiary)',
                        marginTop: 6,
                      }}
                    >
                      {cronDesc.ok ? `Runs: ${cronDesc.text}` : cronDesc.text}
                    </div>
                  </div>
                  <div style={{ marginBottom: 12 }}>
                    <label
                      style={{
                        fontSize: 13,
                        fontWeight: 500,
                        color: 'var(--app-text-primary)',
                        display: 'block',
                        marginBottom: 5,
                      }}
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
                          background: 'var(--app-bg-paper)',
                          border: '1px solid var(--app-border-default)',
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
                        color: 'var(--app-text-primary)',
                        display: 'block',
                        marginBottom: 5,
                      }}
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
                          background: 'var(--app-bg-paper)',
                          border: '1px solid var(--app-border-default)',
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
                            color: 'var(--app-text-primary)',
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
                              background: 'var(--app-bg-paper)',
                              border: '1px solid var(--app-border-default)',
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
                            color: 'var(--app-text-primary)',
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
                              background: 'var(--app-bg-paper)',
                              border: '1px solid var(--app-border-default)',
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

              {kind === 'tracker' && (
                <TrackerTriggerFields
                  projectId={projectId}
                  trackers={trackers}
                  columns={columnData}
                  value={trackerValue}
                  isEdit={isEdit}
                  onChange={setTrackerValue}
                />
              )}

              {/* Chat fields */}
              {kind === 'chat' && (
                <>
                  <ChatChannelFields
                    projectId={projectId}
                    triggerId={editing && editing.chat_provider === chatProvider ? editing.id : undefined}
                    providers={chatProviders}
                    provider={chatProvider}
                    onProviderChange={(key) => {
                      setChatProvider(key);
                      setChatChannelId(null);
                    }}
                    extraChannels={extraChannels}
                    channelId={chatChannelId}
                    onChannelChange={setChatChannelId}
                    onChannelConnected={channelConnected}
                    error={submitted && channelMissing ? 'Choose the channel this trigger listens to' : null}
                    isEdit={isEdit}
                  />
                  <div style={{ display: 'grid', gridTemplateColumns: '150px 1fr', gap: 12 }}>
                    <div>
                      <label
                        style={{
                          fontSize: 13,
                          fontWeight: 500,
                          color: 'var(--app-text-primary)',
                          display: 'block',
                          marginBottom: 5,
                        }}
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
                            background: 'var(--app-bg-paper)',
                            border: '1px solid var(--app-border-default)',
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
                          color: 'var(--app-text-primary)',
                          display: 'block',
                          marginBottom: 5,
                        }}
                      >
                        Pattern
                      </label>
                      <TextInput
                        placeholder="ship it (optional)"
                        value={textContains}
                        onChange={(e) => setTextContains(e.currentTarget.value)}
                        styles={{
                          input: {
                            background: 'var(--app-bg-paper)',
                            border: '1px solid var(--app-border-default)',
                            borderRadius: 5,
                            fontSize: 13,
                          },
                        }}
                      />
                    </div>
                  </div>
                  <div style={{ fontSize: 12, color: 'var(--app-text-tertiary)', marginTop: 4, marginBottom: 12 }}>
                    Matched against the message after the @mention, ignoring case. @mention help lists the commands of a
                    conversation. The words help and connect can&apos;t be used as a pattern.
                  </div>
                  <div style={{ marginBottom: 12 }}>
                    <NumberInput
                      label="Cooldown (s)"
                      description="After a run starts, matching mentions start nothing for this long. 0 starts a run for every matching mention."
                      value={chatCooldown}
                      onChange={setChatCooldown}
                      min={0}
                      styles={{
                        label: { fontSize: 13, fontWeight: 500, color: 'var(--app-text-primary)', marginBottom: 5 },
                        input: {
                          background: 'var(--app-bg-paper)',
                          border: '1px solid var(--app-border-default)',
                          borderRadius: 5,
                          fontSize: 13,
                        },
                      }}
                    />
                  </div>
                  <div style={{ marginBottom: 12 }}>
                    <Select
                      label="Report back in the thread"
                      data={[
                        { value: 'lifecycle', label: 'A status card that follows the run' },
                        { value: 'failures', label: 'Only when a run fails' },
                        { value: 'none', label: 'Nothing' },
                      ]}
                      value={statusReporting}
                      onChange={(v) => setStatusReporting(v ?? 'lifecycle')}
                      allowDeselect={false}
                    />
                  </div>
                  <div style={{ marginBottom: 12 }}>
                    <label
                      style={{
                        fontSize: 13,
                        fontWeight: 500,
                        color: 'var(--app-text-primary)',
                        display: 'block',
                        marginBottom: 5,
                      }}
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
                          background: 'var(--app-bg-paper)',
                          border: '1px solid var(--app-border-default)',
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
                            color: 'var(--app-text-primary)',
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
                              background: 'var(--app-bg-paper)',
                              border: '1px solid var(--app-border-default)',
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
                            color: 'var(--app-text-primary)',
                            display: 'block',
                            marginBottom: 5,
                          }}
                        >
                          Task title template
                        </label>
                        <TextInput
                          placeholder="chat.message — {{date}}"
                          value={subjectTitleTemplate}
                          onChange={(e) => setSubjectTitleTemplate(e.currentTarget.value)}
                          styles={{
                            input: {
                              background: 'var(--app-bg-paper)',
                              border: '1px solid var(--app-border-default)',
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
                            color: 'var(--app-text-primary)',
                            display: 'block',
                            marginBottom: 5,
                          }}
                        >
                          Verification
                        </label>
                        <Select
                          data={[
                            { value: 'shared_token', label: 'Shared token' },
                            { value: 'hmac_sha256', label: 'HMAC SHA-256' },
                            { value: 'none', label: 'None — anyone with the URL can run this workflow' },
                          ]}
                          value={verification}
                          onChange={(v) => setVerification(v ?? 'shared_token')}
                          allowDeselect={false}
                          styles={{
                            input: {
                              background: 'var(--app-bg-paper)',
                              border: '1px solid var(--app-border-default)',
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
                            color: 'var(--app-text-primary)',
                            display: 'block',
                            marginBottom: 5,
                          }}
                        >
                          Secret
                        </label>
                        <PasswordInput
                          placeholder="generated if left blank"
                          value={secret}
                          onChange={(e) => setSecret(e.currentTarget.value)}
                          styles={{
                            input: {
                              background: 'var(--app-bg-paper)',
                              border: '1px solid var(--app-border-default)',
                              borderRadius: 5,
                              fontSize: 13,
                            },
                          }}
                        />
                      </div>
                    </div>
                  )}
                  <div style={{ fontSize: 12, fontWeight: 500, color: 'var(--app-text-secondary)', marginBottom: 8 }}>
                    Only when (optional)
                  </div>
                  <div style={{ display: 'grid', gridTemplateColumns: '1fr 90px 1fr', gap: 10, marginBottom: 12 }}>
                    <div>
                      <label
                        style={{
                          fontSize: 13,
                          fontWeight: 500,
                          color: 'var(--app-text-primary)',
                          display: 'block',
                          marginBottom: 5,
                        }}
                      >
                        Field
                      </label>
                      <TextInput
                        placeholder="ref"
                        value={condField}
                        onChange={(e) => setCondField(e.currentTarget.value)}
                        styles={{
                          input: {
                            background: 'var(--app-bg-paper)',
                            border: '1px solid var(--app-border-default)',
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
                          color: 'var(--app-text-primary)',
                          display: 'block',
                          marginBottom: 5,
                        }}
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
                            background: 'var(--app-bg-paper)',
                            border: '1px solid var(--app-border-default)',
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
                          color: 'var(--app-text-primary)',
                          display: 'block',
                          marginBottom: 5,
                        }}
                      >
                        Value
                      </label>
                      <TextInput
                        placeholder="refs/heads/main"
                        value={condValue}
                        onChange={(e) => setCondValue(e.currentTarget.value)}
                        styles={{
                          input: {
                            background: 'var(--app-bg-paper)',
                            border: '1px solid var(--app-border-default)',
                            borderRadius: 5,
                            fontSize: 13,
                          },
                        }}
                      />
                    </div>
                  </div>
                  <div style={{ marginBottom: 12 }}>
                    <label
                      style={{
                        fontSize: 13,
                        fontWeight: 500,
                        color: 'var(--app-text-primary)',
                        display: 'block',
                        marginBottom: 5,
                      }}
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
                          background: 'var(--app-bg-paper)',
                          border: '1px solid var(--app-border-default)',
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
                            color: 'var(--app-text-primary)',
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
                              background: 'var(--app-bg-paper)',
                              border: '1px solid var(--app-border-default)',
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
                            color: 'var(--app-text-primary)',
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
                              background: 'var(--app-bg-paper)',
                              border: '1px solid var(--app-border-default)',
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
                <div style={{ borderTop: '1px solid var(--app-border-default)', paddingTop: 12, marginTop: 4 }}>
                  <Switch
                    label="Trigger enabled"
                    checked={enabled}
                    onChange={(e) => setEnabled(e.currentTarget.checked)}
                  />
                  <div style={{ fontSize: 12, color: 'var(--app-text-tertiary)', marginTop: 4 }}>
                    Turn this off to pause the trigger. While it is off nothing it listens for starts a run, and what
                    arrives in the meantime is not run when you turn it back on.
                  </div>
                </div>
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
                borderTop: '1px solid var(--app-border-default)',
                flexShrink: 0,
              }}
            >
              <button
                onClick={onClose}
                style={{
                  background: 'none',
                  border: '1px solid var(--app-border-default)',
                  borderRadius: 6,
                  padding: '8px 16px',
                  fontSize: 13,
                  fontWeight: 500,
                  color: 'var(--app-text-secondary)',
                  cursor: 'pointer',
                  fontFamily: 'inherit',
                  transition: 'all 0.12s',
                }}
                onMouseEnter={(e) => {
                  (e.currentTarget as HTMLElement).style.color = 'var(--app-text-primary)';
                  (e.currentTarget as HTMLElement).style.background = 'var(--app-bg-hover)';
                }}
                onMouseLeave={(e) => {
                  (e.currentTarget as HTMLElement).style.color = 'var(--app-text-secondary)';
                  (e.currentTarget as HTMLElement).style.background = 'none';
                }}
              >
                Cancel
              </button>
              <button
                onClick={submit}
                disabled={saving || !workflowId || (kind === 'schedule' && !cronDesc.ok)}
                style={{
                  background:
                    saving || (kind === 'schedule' && !cronDesc.ok)
                      ? 'var(--app-action-selected)'
                      : 'var(--app-primary)',
                  border: 'none',
                  borderRadius: 6,
                  padding: '8px 16px',
                  fontSize: 13,
                  fontWeight: 600,
                  color:
                    saving || (kind === 'schedule' && !cronDesc.ok)
                      ? 'var(--app-accent-muted)'
                      : 'var(--app-on-primary)',
                  cursor: saving || (kind === 'schedule' && !cronDesc.ok) ? 'not-allowed' : 'pointer',
                  fontFamily: 'inherit',
                  transition: 'all 0.12s',
                }}
              >
                {saving ? 'Saving…' : isEdit ? 'Update trigger' : 'Add trigger'}
              </button>
            </div>
          </>
        )}
      </div>
    </>
  );
}

function CopyRow({ label, value }: { label: string; value: string }) {
  return (
    <div style={{ marginBottom: 12 }}>
      <div style={{ fontSize: 13, fontWeight: 500, color: 'var(--app-text-primary)', marginBottom: 5 }}>{label}</div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        <div
          style={{
            flex: 1,
            fontSize: 12,
            fontFamily: 'monospace',
            color: 'var(--app-text-secondary)',
            overflow: 'hidden',
            textOverflow: 'ellipsis',
            whiteSpace: 'nowrap',
          }}
        >
          {value}
        </div>
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
      </div>
    </div>
  );
}

function WebhookCreatedView({
  created,
  onDone,
}: {
  created: { url: string; secret: string; verification: string };
  onDone: () => void;
}) {
  const curl = buildWebhookCurl(created.url, created.secret, created.verification);
  const authLabel =
    created.verification === 'none'
      ? 'no auth'
      : created.verification === 'hmac_sha256'
        ? 'HMAC SHA-256'
        : 'shared token';

  return (
    <>
      <div style={{ flex: 1, overflowY: 'auto', padding: 24 }}>
        <div style={{ fontSize: 14, fontWeight: 600, color: 'var(--app-text-primary)', marginBottom: 4 }}>
          Webhook trigger created
        </div>
        <div style={{ fontSize: 12, color: 'var(--app-text-secondary)', marginBottom: 16, lineHeight: 1.5 }}>
          Point your source at this URL. It is an idempotent start API for this workflow.
        </div>
        <CopyRow label="Request URL" value={created.url} />
        {created.secret && <CopyRow label="Secret" value={created.secret} />}
        <div style={{ marginBottom: 12 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 5 }}>
            <div style={{ fontSize: 13, fontWeight: 500, color: 'var(--app-text-primary)' }}>
              Example request ({authLabel})
            </div>
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
          </div>
          <pre
            style={{
              fontSize: 12,
              fontFamily: 'monospace',
              whiteSpace: 'pre',
              overflowX: 'auto',
              background: 'var(--app-bg-paper)',
              border: '1px solid var(--app-border-default)',
              padding: 8,
              borderRadius: 6,
              margin: 0,
              color: 'var(--app-text-primary)',
            }}
          >
            {curl}
          </pre>
        </div>
        <div style={{ fontSize: 12, color: 'var(--app-text-secondary)' }}>
          Runs the workflow as you — the trigger&apos;s creator.
        </div>
      </div>
      <div
        style={{
          display: 'flex',
          justifyContent: 'flex-end',
          gap: 10,
          padding: '16px 24px',
          borderTop: '1px solid var(--app-border-default)',
          flexShrink: 0,
        }}
      >
        <button
          onClick={onDone}
          style={{
            background: 'var(--app-primary)',
            border: 'none',
            borderRadius: 6,
            padding: '8px 16px',
            fontSize: 13,
            fontWeight: 600,
            color: 'var(--app-on-primary)',
            cursor: 'pointer',
            fontFamily: 'inherit',
          }}
        >
          Done
        </button>
      </div>
    </>
  );
}

interface ChatChannelFieldsProps {
  projectId: number;
  triggerId?: number;
  providers: ChatProviderOption[];
  provider: string;
  onProviderChange: (key: string) => void;
  extraChannels: ChatConversationOption[];
  channelId: number | null;
  onChannelChange: (id: number) => void;
  onChannelConnected: (channel: ChatChannel) => void;
  error: string | null;
  isEdit: boolean;
}

function channelOptions(channels: ChatConversationOption[]): ComboboxData {
  const ungrouped: ComboboxItem[] = [];
  const groups = new Map<string, ComboboxItem[]>();
  for (const c of channels) {
    const item = { value: String(c.id), label: c.label };
    const group = c.kind === 'group' ? 'Group chats' : c.teamName;
    if (group) groups.set(group, [...(groups.get(group) ?? []), item]);
    else ungrouped.push(item);
  }
  return [...ungrouped, ...[...groups.entries()].map(([group, items]) => ({ group, items }))];
}

// Which messenger, and the one channel in it the trigger listens to. Only
// channels connected to the company are offered: a channel is connected by
// posting a code in it, never by typing its id.
function ChatChannelFields({
  projectId,
  triggerId,
  providers,
  provider,
  onProviderChange,
  extraChannels,
  channelId,
  onChannelChange,
  onChannelConnected,
  error,
  isEdit,
}: ChatChannelFieldsProps) {
  const [connecting, setConnecting] = useState(false);
  const current = providers.find((p) => p.key === provider);
  const providerLabel = CHAT_PROVIDER_LABELS[provider] ?? provider;
  const providerData = providers.map((p) => ({ value: p.key, label: p.label }));
  if (!current) providerData.push({ value: provider, label: `${providerLabel} (not connected)` });

  const listed = current?.conversations ?? [];
  const channels = [
    ...listed,
    ...extraChannels.filter((c) => c.provider === provider && !listed.some((l) => l.id === c.id)),
  ];

  return (
    <>
      <div style={{ marginBottom: 12 }}>
        <Select
          label="Messenger"
          data={providerData}
          value={provider}
          onChange={(v) => v && onProviderChange(v)}
          allowDeselect={false}
          disabled={isEdit && providerData.length < 2}
        />
        {providers.length === 0 && (
          <div style={{ fontSize: 12, color: 'var(--app-text-tertiary)', marginTop: 4 }}>
            Connect Slack or Microsoft Teams on the Integrations page first.
          </div>
        )}
      </div>
      <div style={{ marginBottom: 12 }}>
        <Select
          label="Channel"
          description={
            channels.length > 0
              ? 'The one channel this trigger listens to. Only channels connected to your company are listed.'
              : `No ${providerLabel} channel is connected to your company yet.`
          }
          placeholder={channels.length > 0 ? 'Choose a channel' : 'No channel connected yet'}
          data={channelOptions(channels)}
          value={channelId === null ? null : String(channelId)}
          onChange={(v) => v && onChannelChange(Number(v))}
          allowDeselect={false}
          searchable
          nothingFoundMessage={
            channels.length > 0 ? 'No channel matches' : 'Connect a new channel with the button below'
          }
          error={error}
        />
        {current && (
          <Button
            variant="subtle"
            size="compact-sm"
            mt={6}
            leftSection={<IconPlus size={14} />}
            onClick={() => setConnecting(true)}
          >
            Connect a new channel…
          </Button>
        )}
      </div>
      {current && (
        <ConnectChannelModal
          projectId={projectId}
          provider={provider}
          triggerId={triggerId}
          opened={connecting}
          onClose={() => setConnecting(false)}
          onConnected={onChannelConnected}
        />
      )}
    </>
  );
}
