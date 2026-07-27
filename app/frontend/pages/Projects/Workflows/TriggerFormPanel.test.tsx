import '@testing-library/jest-dom/vitest';
import type { ComponentProps } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent, waitFor } from 'test/renderPage';

import { TriggerFormPanel } from './TriggerFormPanel';
import type { Trigger } from './TriggersTab';

// TriggerFormPanel takes plain props (no usePage/useForm read) and talks to the backend through
// apiFetch() -> the global fetch() the test setup stubs. `defaultKind` seeds the create-mode kind and
// `editing` puts the form into (kind-locked) edit mode, so each trigger kind and its per-kind branches
// can be rendered directly without driving the kind Select. Tests that assert a request spy on fetch()
// and dispatch by HTTP method, mirroring WorkflowTriggersDrawer.test.tsx.

type PanelProps = ComponentProps<typeof TriggerFormPanel>;

// ColumnOption / StepOption / Trigger are local interfaces (no Typelizer type, so no factory exists);
// these literals match those interfaces exactly, mirroring how WorkflowTriggersDrawer.test.tsx inlines
// its Column/Trigger fixtures.
const columns: PanelProps['columns'] = [
  { id: 1, name: 'Backlog' },
  { id: 2, name: 'In Progress', boundWorkflowName: 'Other Flow' },
];

const sessions: PanelProps['sessions'] = [
  { id: 10, name: 'Triage' },
  { id: 11, name: 'Build' },
];

const baseProps = (overrides: Partial<PanelProps> = {}): PanelProps => ({
  projectId: 7,
  workflowId: 3,
  columns,
  sessions,
  editing: null,
  defaultKind: 'column',
  onClose: vi.fn(),
  onSaved: vi.fn(),
  ...overrides,
});

const json = (body: unknown, status = 200): Response =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

// The panel issues exactly one POST (create) or PATCH (edit) per submit; return a fresh Response each
// call so its body is always readable.
function installFetch(make: () => Response = () => json({})) {
  return vi.spyOn(globalThis, 'fetch').mockImplementation(() => Promise.resolve(make()));
}

const bodyOf = (spy: ReturnType<typeof installFetch>, method: string) => {
  const call = spy.mock.calls.find((c) => (c[1] as RequestInit | undefined)?.method === method);
  if (!call) throw new Error(`no ${method} call recorded`);
  return JSON.parse((call[1] as RequestInit).body as string);
};

// Opens a Mantine Select by its current display value, then clicks the option whose name matches.
async function pickOption(currentDisplay: RegExp | string, optionName: RegExp | string) {
  await userEvent.click(screen.getByDisplayValue(currentDisplay));
  await userEvent.click(await screen.findByRole('option', { name: optionName }));
}

afterEach(() => {
  vi.restoreAllMocks();
});

describe('Projects/Workflows/TriggerFormPanel', () => {
  // -------------------------------------------------------------------------
  // Create mode — kind selector + column defaults
  // -------------------------------------------------------------------------
  it('renders the create header, an editable kind selector, and the column fields by default', () => {
    renderPage(<TriggerFormPanel {...baseProps()} />);

    // "Add trigger" is both the header title and the footer submit button in create mode.
    expect(screen.getAllByText('Add trigger')).toHaveLength(2);
    // The kind is editable in create mode (not the locked read-only label of edit mode).
    expect(screen.getByDisplayValue('Task enters column')).toBeInTheDocument();
    expect(screen.queryByText('Type is locked when editing')).not.toBeInTheDocument();
    // Column-kind fields.
    expect(screen.getByText('Column')).toBeInTheDocument();
    expect(screen.getByText('Mode')).toBeInTheDocument();
    expect(screen.getByText('Cooldown (s)')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Auto' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Manual' })).toBeInTheDocument();
    // Footer actions.
    expect(screen.getByRole('button', { name: 'Add trigger' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Cancel' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Close' })).toBeInTheDocument();
  });

  it('switches the rendered fields when the kind Select changes to slack', async () => {
    renderPage(<TriggerFormPanel {...baseProps()} />);

    // Kind is the first combobox; changing it swaps the per-kind field block.
    const [kindSelect] = screen.getAllByRole('combobox');
    await userEvent.click(kindSelect);
    await userEvent.click(await screen.findByRole('option', { name: 'Slack message' }));

    expect(screen.getByPlaceholderText('C0123ABC (blank = any)')).toBeInTheDocument();
    expect(screen.queryByText('Mode')).not.toBeInTheDocument();
  });

  it('posts a column trigger with the default column, mode, and cooldown and calls onSaved', async () => {
    const onSaved = vi.fn();
    const fetchSpy = installFetch();

    renderPage(<TriggerFormPanel {...baseProps({ onSaved })} />);

    await userEvent.click(screen.getByRole('button', { name: 'Add trigger' }));

    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        '/api/v1/projects/7/workflows/3/triggers',
        expect.objectContaining({ method: 'POST' }),
      ),
    );
    // columns[0] (Backlog, unbound) is the default column; mode/cooldown keep their initial values.
    expect(bodyOf(fetchSpy, 'POST')).toEqual({
      trigger: { kind: 'column', board_column_id: '1', trigger_mode: 'auto', cooldown_seconds: 5 },
    });
    await waitFor(() => expect(onSaved).toHaveBeenCalled());
  });

  it('posts a column trigger with manual mode after toggling it', async () => {
    const fetchSpy = installFetch();

    renderPage(<TriggerFormPanel {...baseProps()} />);

    await userEvent.click(screen.getByRole('button', { name: 'Manual' }));
    await userEvent.click(screen.getByRole('button', { name: 'Add trigger' }));

    await waitFor(() => expect(fetchSpy).toHaveBeenCalled());
    expect(bodyOf(fetchSpy, 'POST').trigger.trigger_mode).toBe('manual');
  });

  // -------------------------------------------------------------------------
  // Schedule kind — cron validation + submit
  // -------------------------------------------------------------------------
  it('describes a valid cron, disables submit on empty and invalid cron', async () => {
    installFetch();

    renderPage(<TriggerFormPanel {...baseProps({ defaultKind: 'schedule' })} />);

    // Default cron is valid: a human-readable description shows and submit is enabled.
    expect(screen.getByText(/^Runs:/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add trigger' })).toBeEnabled();

    const cronInput = screen.getByPlaceholderText('0 9 * * 1-5');
    await userEvent.clear(cronInput);
    // Empty cron: prompt + disabled submit (no "Invalid cron" field error because the input is blank).
    expect(await screen.findByText('Enter a cron expression')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add trigger' })).toBeDisabled();

    await userEvent.type(cronInput, 'zzz');
    // Invalid cron: parse-error description + the input-level "Invalid cron" error + disabled submit.
    expect(await screen.findByText('Not a valid cron expression')).toBeInTheDocument();
    expect(screen.getByText('Invalid cron')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add trigger' })).toBeDisabled();
  });

  it('posts a schedule trigger with its cron/timezone and an empty filter when no subject is set', async () => {
    const fetchSpy = installFetch();

    renderPage(<TriggerFormPanel {...baseProps({ defaultKind: 'schedule' })} />);

    await userEvent.click(screen.getByRole('button', { name: 'Add trigger' }));

    await waitFor(() => expect(fetchSpy).toHaveBeenCalled());
    expect(bodyOf(fetchSpy, 'POST').trigger).toEqual({
      kind: 'schedule',
      schedule_config: { cron: '0 9 * * 1-5', timezone: 'UTC' },
      filter_predicate: {},
      subject_policy: 'none',
    });
  });

  it('reveals the task column/title fields and posts the subject block when create_task is chosen', async () => {
    const fetchSpy = installFetch();

    renderPage(<TriggerFormPanel {...baseProps({ defaultKind: 'schedule' })} />);

    await pickOption(/project-level run/, 'Create a task');

    expect(await screen.findByText('Task column')).toBeInTheDocument();
    const titleInput = screen.getByPlaceholderText(/webhook\.received/);
    await userEvent.type(titleInput, 'nightly digest');

    await userEvent.click(screen.getByRole('button', { name: 'Add trigger' }));

    await waitFor(() => expect(fetchSpy).toHaveBeenCalled());
    const trigger = bodyOf(fetchSpy, 'POST').trigger;
    expect(trigger.subject_policy).toBe('create_task'); // TriggerBinding enum, not a session id
    expect(trigger.subject_column_id).toBe('1'); // default columns[0]
    expect(trigger.subject_title_template).toBe('nightly digest');
  });

  // -------------------------------------------------------------------------
  // Slack kind
  // -------------------------------------------------------------------------
  it('posts a slack trigger with the channel and a text predicate', async () => {
    const fetchSpy = installFetch();

    renderPage(<TriggerFormPanel {...baseProps({ defaultKind: 'slack' })} />);

    await userEvent.type(screen.getByPlaceholderText('C0123ABC (blank = any)'), 'C42');
    await userEvent.type(screen.getByPlaceholderText('ship it (optional)'), 'deploy');
    await userEvent.click(screen.getByRole('button', { name: 'Add trigger' }));

    await waitFor(() => expect(fetchSpy).toHaveBeenCalled());
    expect(bodyOf(fetchSpy, 'POST').trigger).toEqual({
      kind: 'slack',
      filter_predicate: { channel: 'C42', text: { op: 'contains', value: 'deploy' } },
      subject_policy: 'none',
    });
  });

  it('posts an empty slack filter when channel and pattern are left blank', async () => {
    const fetchSpy = installFetch();

    renderPage(<TriggerFormPanel {...baseProps({ defaultKind: 'slack' })} />);

    await userEvent.click(screen.getByRole('button', { name: 'Add trigger' }));

    await waitFor(() => expect(fetchSpy).toHaveBeenCalled());
    expect(bodyOf(fetchSpy, 'POST').trigger.filter_predicate).toEqual({});
  });

  it('reveals and posts the slack subject block with its own title placeholder', async () => {
    const fetchSpy = installFetch();

    renderPage(<TriggerFormPanel {...baseProps({ defaultKind: 'slack' })} />);

    await pickOption(/project-level run/, 'Create a task');

    expect(await screen.findByText('Task column')).toBeInTheDocument();
    await userEvent.type(screen.getByPlaceholderText(/slack\.message/), 'from slack');
    await userEvent.click(screen.getByRole('button', { name: 'Add trigger' }));

    await waitFor(() => expect(fetchSpy).toHaveBeenCalled());
    const trigger = bodyOf(fetchSpy, 'POST').trigger;
    expect(trigger.subject_policy).toBe('create_task'); // TriggerBinding enum, not a session id
    expect(trigger.subject_title_template).toBe('from slack');
  });

  // -------------------------------------------------------------------------
  // Webhook kind
  // -------------------------------------------------------------------------
  it('posts a webhook trigger with verification, secret, and an eq filter', async () => {
    const fetchSpy = installFetch();

    renderPage(<TriggerFormPanel {...baseProps({ defaultKind: 'webhook' })} />);

    // Verification + secret only appear on create (immutable after creation).
    await pickOption('None', 'HMAC SHA-256');
    await userEvent.type(screen.getByPlaceholderText('optional'), 'sek');
    await userEvent.type(screen.getByPlaceholderText('ref'), 'branch');
    await userEvent.type(screen.getByPlaceholderText('refs/heads/main'), 'main');
    await userEvent.click(screen.getByRole('button', { name: 'Add trigger' }));

    await waitFor(() => expect(fetchSpy).toHaveBeenCalled());
    // condOp defaults to 'eq', so the value is stored directly (not wrapped in an {op,value} object).
    expect(bodyOf(fetchSpy, 'POST').trigger).toEqual({
      kind: 'webhook',
      verification_strategy: 'hmac_sha256',
      secret: 'sek',
      filter_predicate: { branch: 'main' },
      subject_policy: 'none',
    });
  });

  it('posts a webhook trigger with no secret and an empty filter when the optional fields are blank', async () => {
    const fetchSpy = installFetch();

    renderPage(<TriggerFormPanel {...baseProps({ defaultKind: 'webhook' })} />);

    await userEvent.click(screen.getByRole('button', { name: 'Add trigger' }));

    await waitFor(() => expect(fetchSpy).toHaveBeenCalled());
    expect(bodyOf(fetchSpy, 'POST').trigger).toEqual({
      kind: 'webhook',
      verification_strategy: 'none',
      filter_predicate: {},
      subject_policy: 'none',
    });
  });

  it('reveals the webhook subject block when create_task is chosen', async () => {
    installFetch();

    renderPage(<TriggerFormPanel {...baseProps({ defaultKind: 'webhook' })} />);

    expect(screen.queryByText('Task column')).not.toBeInTheDocument();
    await pickOption(/project-level run/, 'Create a task');
    expect(await screen.findByText('Task column')).toBeInTheDocument();
  });

  // -------------------------------------------------------------------------
  // Edit mode — kind locked, seeded from the trigger
  // -------------------------------------------------------------------------
  it('locks the kind and patches a column trigger with the kind query param', async () => {
    const editing: Trigger = {
      id: 1,
      kind: 'column',
      event_type: 'task.entered_column',
      board_column_id: 1,
      trigger_mode: 'manual',
      cooldown_seconds: 30,
    };
    const fetchSpy = installFetch();

    renderPage(<TriggerFormPanel {...baseProps({ editing })} />);

    // Type is a locked read-only label in edit mode, not a Select.
    expect(screen.getByText('Type is locked when editing')).toBeInTheDocument();
    expect(screen.getByText('Task enters column')).toBeInTheDocument();
    // A column edit has no Enabled switch (that only shows for non-column kinds).
    expect(screen.queryByRole('switch', { name: 'Enabled' })).not.toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Update trigger' }));

    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        '/api/v1/projects/7/workflows/3/triggers/1?kind=column',
        expect.objectContaining({ method: 'PATCH' }),
      ),
    );
    // Column edits omit board_column_id (immutable) and never touch the subject/enabled block.
    expect(bodyOf(fetchSpy, 'PATCH').trigger).toEqual({ trigger_mode: 'manual', cooldown_seconds: 30 });
  });

  it('seeds a slack edit from a structured text predicate and patches enabled + filter', async () => {
    const editing: Trigger = {
      id: 2,
      kind: 'slack',
      event_type: 'slack.message',
      filter_predicate: { channel: 'C1', text: { op: 'regex', value: 'deploy' } },
      subject_policy: 'none',
      enabled: true,
    };
    const fetchSpy = installFetch();

    renderPage(<TriggerFormPanel {...baseProps({ editing })} />);

    expect(screen.getByPlaceholderText('C0123ABC (blank = any)')).toHaveValue('C1');
    expect(screen.getByPlaceholderText('ship it (optional)')).toHaveValue('deploy');
    const enabledSwitch = screen.getByRole('switch', { name: 'Enabled' });
    expect(enabledSwitch).toBeChecked();

    await userEvent.click(enabledSwitch); // toggle off
    await userEvent.click(screen.getByRole('button', { name: 'Update trigger' }));

    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        '/api/v1/projects/7/workflows/3/triggers/2',
        expect.objectContaining({ method: 'PATCH' }),
      ),
    );
    const trigger = bodyOf(fetchSpy, 'PATCH').trigger;
    expect(trigger.filter_predicate).toEqual({ channel: 'C1', text: { op: 'regex', value: 'deploy' } });
    expect(trigger.enabled).toBe(false);
    expect(trigger.kind).toBeUndefined(); // edits never resend the (locked) kind
  });

  it('seeds a slack edit from a plain-string text predicate', () => {
    const editing: Trigger = {
      id: 2,
      kind: 'slack',
      event_type: 'slack.message',
      filter_predicate: { channel: 'C2', text: 'shipit' },
      subject_policy: 'none',
      enabled: true,
    };

    renderPage(<TriggerFormPanel {...baseProps({ editing })} />);

    expect(screen.getByPlaceholderText('C0123ABC (blank = any)')).toHaveValue('C2');
    expect(screen.getByPlaceholderText('ship it (optional)')).toHaveValue('shipit');
  });

  it('seeds a slack edit with a channel but no text predicate', () => {
    const editing: Trigger = {
      id: 2,
      kind: 'slack',
      event_type: 'slack.message',
      filter_predicate: { channel: 'C3' },
      subject_policy: 'none',
      enabled: false,
    };

    renderPage(<TriggerFormPanel {...baseProps({ editing })} />);

    expect(screen.getByPlaceholderText('C0123ABC (blank = any)')).toHaveValue('C3');
    expect(screen.getByPlaceholderText('ship it (optional)')).toHaveValue('');
    // enabled:false trigger => the switch reflects that.
    expect(screen.getByRole('switch', { name: 'Enabled' })).not.toBeChecked();
  });

  it('seeds a slack edit from a structured text predicate missing op/value', () => {
    const editing: Trigger = {
      id: 2,
      kind: 'slack',
      event_type: 'slack.message',
      filter_predicate: { channel: 'C4', text: {} },
      subject_policy: 'none',
      enabled: true,
    };

    renderPage(<TriggerFormPanel {...baseProps({ editing })} />);

    expect(screen.getByPlaceholderText('C0123ABC (blank = any)')).toHaveValue('C4');
    // Missing op/value fall back to 'contains'/'' (the empty pattern reflects the '' fallback).
    expect(screen.getByPlaceholderText('ship it (optional)')).toHaveValue('');
  });

  it('seeds a webhook edit from a structured predicate, hides verification, and patches an {op,value} filter', async () => {
    const editing: Trigger = {
      id: 5,
      kind: 'webhook',
      event_type: 'webhook.received',
      filter_predicate: { ref: { op: 'contains', value: 'main' } },
      subject_policy: 'none',
      enabled: false,
    };
    const fetchSpy = installFetch();

    renderPage(<TriggerFormPanel {...baseProps({ editing })} />);

    // Verification/secret are create-only; absent when editing.
    expect(screen.queryByText('Verification')).not.toBeInTheDocument();
    expect(screen.getByPlaceholderText('ref')).toHaveValue('ref');
    expect(screen.getByPlaceholderText('refs/heads/main')).toHaveValue('main');
    expect(screen.getByRole('switch', { name: 'Enabled' })).not.toBeChecked();

    await userEvent.click(screen.getByRole('button', { name: 'Update trigger' }));

    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        '/api/v1/projects/7/workflows/3/triggers/5',
        expect.objectContaining({ method: 'PATCH' }),
      ),
    );
    const trigger = bodyOf(fetchSpy, 'PATCH').trigger;
    // Non-eq op wraps the value in an {op,value} object; no verification_strategy/secret on edit.
    expect(trigger.filter_predicate).toEqual({ ref: { op: 'contains', value: 'main' } });
    expect(trigger.verification_strategy).toBeUndefined();
    expect(trigger.enabled).toBe(false);
  });

  it('seeds a webhook edit from a plain-scalar predicate', () => {
    const editing: Trigger = {
      id: 5,
      kind: 'webhook',
      event_type: 'webhook.received',
      filter_predicate: { branch: 'develop' },
      subject_policy: 'none',
      enabled: true,
    };

    renderPage(<TriggerFormPanel {...baseProps({ editing })} />);

    expect(screen.getByPlaceholderText('ref')).toHaveValue('branch');
    expect(screen.getByPlaceholderText('refs/heads/main')).toHaveValue('develop');
  });

  it('seeds an empty webhook edit from an empty predicate', () => {
    const editing: Trigger = {
      id: 5,
      kind: 'webhook',
      event_type: 'webhook.received',
      filter_predicate: {},
      subject_policy: 'none',
      enabled: true,
    };

    renderPage(<TriggerFormPanel {...baseProps({ editing })} />);

    expect(screen.getByPlaceholderText('ref')).toHaveValue('');
    expect(screen.getByPlaceholderText('refs/heads/main')).toHaveValue('');
  });

  it('seeds a webhook edit from a structured predicate whose value is null', () => {
    const editing: Trigger = {
      id: 5,
      kind: 'webhook',
      event_type: 'webhook.received',
      filter_predicate: { ref: { value: null } },
      subject_policy: 'none',
      enabled: true,
    };

    renderPage(<TriggerFormPanel {...baseProps({ editing })} />);

    expect(screen.getByPlaceholderText('ref')).toHaveValue('ref');
    // null value => empty string (missing op falls back to 'eq').
    expect(screen.getByPlaceholderText('refs/heads/main')).toHaveValue('');
  });

  it('seeds a schedule edit and patches its config plus the enabled flag', async () => {
    const editing: Trigger = {
      id: 6,
      kind: 'schedule',
      event_type: 'schedule.tick',
      schedule_config: { cron: '*/5 * * * *', timezone: 'America/New_York' },
      subject_policy: 'none',
    };
    const fetchSpy = installFetch();

    renderPage(<TriggerFormPanel {...baseProps({ editing })} />);

    expect(screen.getByPlaceholderText('0 9 * * 1-5')).toHaveValue('*/5 * * * *');
    // enabled defaults to true when the trigger omits it; schedule is non-column so the switch shows.
    expect(screen.getByRole('switch', { name: 'Enabled' })).toBeChecked();

    await userEvent.click(screen.getByRole('button', { name: 'Update trigger' }));

    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        '/api/v1/projects/7/workflows/3/triggers/6',
        expect.objectContaining({ method: 'PATCH' }),
      ),
    );
    expect(bodyOf(fetchSpy, 'PATCH').trigger).toEqual({
      schedule_config: { cron: '*/5 * * * *', timezone: 'America/New_York' },
      filter_predicate: {},
      subject_policy: 'none',
      enabled: true,
    });
  });

  // -------------------------------------------------------------------------
  // Error handling + close
  // -------------------------------------------------------------------------
  it('shows the joined server errors and does not call onSaved when the save fails', async () => {
    const onSaved = vi.fn();
    installFetch(() => json({ errors: ['Bad channel', 'Nope'] }, 422));

    renderPage(<TriggerFormPanel {...baseProps({ defaultKind: 'slack', onSaved })} />);

    await userEvent.click(screen.getByRole('button', { name: 'Add trigger' }));

    expect(await screen.findByText('Bad channel, Nope')).toBeInTheDocument();
    expect(onSaved).not.toHaveBeenCalled();
  });

  it('falls back to a generic error message when the failed response has no parseable body', async () => {
    const onSaved = vi.fn();
    // Invalid JSON => res.json() rejects => caught as {} => default message.
    installFetch(() => new Response('boom', { status: 500, headers: { 'Content-Type': 'application/json' } }));

    renderPage(<TriggerFormPanel {...baseProps({ defaultKind: 'slack', onSaved })} />);

    await userEvent.click(screen.getByRole('button', { name: 'Add trigger' }));

    expect(await screen.findByText('Failed to save trigger')).toBeInTheDocument();
    expect(onSaved).not.toHaveBeenCalled();
  });

  it('calls onClose from the Cancel button', async () => {
    const onClose = vi.fn();
    renderPage(<TriggerFormPanel {...baseProps({ onClose })} />);

    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('calls onClose from the header close button', async () => {
    const onClose = vi.fn();
    renderPage(<TriggerFormPanel {...baseProps({ onClose })} />);

    await userEvent.click(screen.getByRole('button', { name: 'Close' }));
    expect(onClose).toHaveBeenCalledTimes(1);
  });
});
