import '@testing-library/jest-dom/vitest';
import type { ComponentProps } from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent, waitFor } from 'test/renderPage';

import { TriggersTab } from './TriggersTab';

type TabProps = ComponentProps<typeof TriggersTab>;

// TriggersTab takes plain props (no usePage read) and talks to the backend through apiFetch(), a thin
// wrapper over the global fetch() the test setup stubs. Each test that asserts a request (or needs
// seeded triggers) spies on fetch() and dispatches by HTTP method, exactly like the sibling
// WorkflowTriggersDrawer.test.tsx in this directory.

// ColumnOption / StepOption / Trigger are the component's own local interfaces (no Typelizer type, so
// no factory exists); these literals match those interfaces exactly.
const columns: TabProps['columns'] = [
  { id: 1, name: 'Backlog' },
  { id: 2, name: 'In Progress', boundWorkflowName: 'Other Flow' },
];

const sessions: TabProps['sessions'] = [{ id: 10, name: 'Draft PR' }];

const baseProps = (overrides: Partial<TabProps> = {}): TabProps => ({
  projectId: 7,
  workflowId: 3,
  columns,
  sessions,
  readOnly: false,
  ...overrides,
});

const columnTrigger = (o: Record<string, unknown> = {}) => ({
  id: 1,
  kind: 'column',
  event_type: 'task.entered_column',
  column_name: 'Backlog',
  trigger_mode: 'auto',
  cooldown_seconds: 5,
  board_column_id: 1,
  enabled: true,
  ...o,
});

const slackTrigger = (o: Record<string, unknown> = {}) => ({
  id: 2,
  kind: 'slack',
  event_type: 'slack.message',
  filter_predicate: { channel: 'C1', text: { op: 'contains', value: 'ship' } },
  enabled: true,
  ...o,
});

const scheduleTrigger = (o: Record<string, unknown> = {}) => ({
  id: 3,
  kind: 'schedule',
  event_type: 'schedule.tick',
  schedule_config: { cron: '* * * * *', timezone: 'UTC' },
  enabled: true,
  ...o,
});

const webhookTrigger = (o: Record<string, unknown> = {}) => ({
  id: 4,
  kind: 'webhook',
  event_type: 'webhook.received',
  filter_predicate: {},
  enabled: true,
  ...o,
});

const json = (body: unknown, status = 200): Response =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

// Install a fetch spy returning `triggers` for the GET (load) and controllable responses per verb.
function installFetch(opts: { triggers?: unknown[]; deleteOk?: boolean; patchOk?: boolean; postBody?: unknown } = {}) {
  const { triggers = [], deleteOk = true, patchOk = true, postBody = {} } = opts;
  return vi.spyOn(globalThis, 'fetch').mockImplementation((_input, init) => {
    const method = init?.method;
    if (method === 'DELETE') return Promise.resolve(json({}, deleteOk ? 200 : 500));
    if (method === 'PATCH') return Promise.resolve(json({}, patchOk ? 200 : 500));
    if (method === 'POST') return Promise.resolve(json(postBody));
    return Promise.resolve(json({ triggers }));
  });
}

const callBody = (spy: ReturnType<typeof installFetch>, method: string) => {
  const call = spy.mock.calls.find((c) => (c[1] as RequestInit | undefined)?.method === method);
  if (!call) throw new Error(`no ${method} call recorded`);
  return JSON.parse((call[1] as RequestInit).body as string);
};

const getCallCount = (spy: ReturnType<typeof installFetch>) =>
  spy.mock.calls.filter((c) => !(c[1] as RequestInit | undefined)?.method).length;

// Row action buttons (edit/delete) are icon-only with no accessible name; the only labelled button in
// the card grid is the "Add a trigger" tile. With a single trigger rendered (not read-only) the button
// order is deterministic: [edit, delete, add-tile].
const rowButtons = () => screen.getAllByRole('button');

let consoleErrorSpy: ReturnType<typeof vi.spyOn>;

beforeEach(() => {
  consoleErrorSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
});

afterEach(() => {
  vi.restoreAllMocks();
});

describe('Projects/Workflows/TriggersTab', () => {
  it('shows a loading state (no list/empty-state) while the initial fetch is pending', async () => {
    let resolveGet: (r: Response) => void = () => {};
    const getPromise = new Promise<Response>((r) => {
      resolveGet = r;
    });
    vi.spyOn(globalThis, 'fetch').mockImplementation((_input, init) =>
      init?.method ? Promise.resolve(json({})) : getPromise,
    );

    renderPage(<TriggersTab {...baseProps()} />);

    // Heading always renders; while loading, neither the empty state nor a card grid is shown.
    expect(screen.getByText(/how this workflow launches/)).toBeInTheDocument();
    expect(screen.queryByText('Add your first trigger')).not.toBeInTheDocument();

    resolveGet(json({ triggers: [] }));

    expect(await screen.findByText('Add your first trigger')).toBeInTheDocument();
  });

  it('shows the empty state with all four trigger-kind choices when not read-only', async () => {
    installFetch({ triggers: [] });

    renderPage(<TriggersTab {...baseProps()} />);

    expect(await screen.findByText('Add your first trigger')).toBeInTheDocument();
    expect(screen.getByText('Task enters column')).toBeInTheDocument();
    expect(screen.getByText('On schedule')).toBeInTheDocument();
    expect(screen.getByText('Slack message')).toBeInTheDocument();
    expect(screen.getByText('Incoming webhook')).toBeInTheDocument();
  });

  it('hides the trigger-kind choices in the empty state when read-only', async () => {
    installFetch({ triggers: [] });

    renderPage(<TriggersTab {...baseProps({ readOnly: true })} />);

    expect(await screen.findByText('Add your first trigger')).toBeInTheDocument();
    // The choice cards live inside a `!readOnly` block.
    expect(screen.queryByText('On schedule')).not.toBeInTheDocument();
    expect(screen.queryByText('Slack message')).not.toBeInTheDocument();
  });

  it('renders a column trigger card with title, meta, and event badge', async () => {
    installFetch({ triggers: [columnTrigger()] });

    renderPage(<TriggersTab {...baseProps()} />);

    expect(await screen.findByText('Task enters "Backlog"')).toBeInTheDocument();
    expect(screen.getByText('auto · cooldown 5s')).toBeInTheDocument();
    expect(screen.getByText('BOARD.COLUMN_CHANGED')).toBeInTheDocument();
  });

  it('falls back to defaults for a column trigger missing name/mode/cooldown', async () => {
    installFetch({
      triggers: [columnTrigger({ column_name: undefined, trigger_mode: undefined, cooldown_seconds: undefined })],
    });

    renderPage(<TriggersTab {...baseProps()} />);

    expect(await screen.findByText('Task enters "column"')).toBeInTheDocument();
    expect(screen.getByText('auto · cooldown 0s')).toBeInTheDocument();
  });

  it('renders a schedule trigger with a human cron description and meta', async () => {
    installFetch({ triggers: [scheduleTrigger()] });

    renderPage(<TriggersTab {...baseProps()} />);

    // describeCronShort('* * * * *') => 'Every minute' (cronstrue, stable across versions).
    expect(await screen.findByText('Every minute')).toBeInTheDocument();
    expect(screen.getByText('* * * * * · UTC')).toBeInTheDocument();
    expect(screen.getByText('SCHEDULE.CRON')).toBeInTheDocument();
  });

  it('renders a schedule trigger with an invalid cron using the raw fallback', async () => {
    installFetch({ triggers: [scheduleTrigger({ schedule_config: { cron: 'zzz', timezone: 'UTC' } })] });

    renderPage(<TriggersTab {...baseProps()} />);

    // cronstrue throws -> title falls back to `Cron zzz`; meta echoes the raw cron.
    expect(await screen.findByText('Cron zzz')).toBeInTheDocument();
    expect(screen.getByText('zzz · UTC')).toBeInTheDocument();
  });

  it('renders a schedule trigger with no config using — and UTC defaults', async () => {
    installFetch({ triggers: [scheduleTrigger({ schedule_config: undefined })] });

    renderPage(<TriggersTab {...baseProps()} />);

    expect(await screen.findByText('— · UTC')).toBeInTheDocument();
  });

  it('renders a matching slack trigger with quoted text and channel meta', async () => {
    installFetch({ triggers: [slackTrigger()] });

    renderPage(<TriggersTab {...baseProps()} />);

    expect(await screen.findByText('Slack message contains "ship"')).toBeInTheDocument();
    expect(screen.getByText('channel C1')).toBeInTheDocument();
    expect(screen.getByText('SLACK.MESSAGE')).toBeInTheDocument();
  });

  it('renders a slack trigger with a custom op and no channel', async () => {
    installFetch({ triggers: [slackTrigger({ filter_predicate: { text: { op: 'eq', value: 'deploy' } } })] });

    renderPage(<TriggersTab {...baseProps()} />);

    expect(await screen.findByText('Slack message eq "deploy"')).toBeInTheDocument();
    expect(screen.getByText('any channel')).toBeInTheDocument();
  });

  it('defaults the slack op to "contains" when the predicate omits it', async () => {
    installFetch({ triggers: [slackTrigger({ filter_predicate: { text: { value: 'ping' } } })] });

    renderPage(<TriggersTab {...baseProps()} />);

    expect(await screen.findByText('Slack message contains "ping"')).toBeInTheDocument();
  });

  it('renders "Any Slack message" when the text filter has no value', async () => {
    installFetch({ triggers: [slackTrigger({ filter_predicate: { text: { op: 'contains' } } })] });

    renderPage(<TriggersTab {...baseProps()} />);

    expect(await screen.findByText('Any Slack message')).toBeInTheDocument();
  });

  it('renders "Any Slack message" / "any channel" when there is no filter', async () => {
    installFetch({ triggers: [slackTrigger({ filter_predicate: {} })] });

    renderPage(<TriggersTab {...baseProps()} />);

    expect(await screen.findByText('Any Slack message')).toBeInTheDocument();
    expect(screen.getByText('any channel')).toBeInTheDocument();
  });

  it('renders a webhook trigger with verification strategy and object condition meta', async () => {
    installFetch({
      triggers: [
        webhookTrigger({
          verification_strategy: 'hmac_sha256',
          filter_predicate: { ref: { op: 'eq', value: 'refs/heads/main' } },
        }),
      ],
    });

    renderPage(<TriggersTab {...baseProps()} />);

    expect(await screen.findByText('Incoming webhook')).toBeInTheDocument();
    expect(screen.getByText('verification: hmac_sha256 · when ref eq refs/heads/main')).toBeInTheDocument();
    expect(screen.getByText('WEBHOOK.RECEIVED')).toBeInTheDocument();
  });

  it('defaults the webhook condition op to eq for an object value without op', async () => {
    installFetch({ triggers: [webhookTrigger({ filter_predicate: { ref: { value: 'main' } } })] });

    renderPage(<TriggersTab {...baseProps()} />);

    expect(await screen.findByText('verification: none · when ref eq main')).toBeInTheDocument();
  });

  it('renders a webhook trigger with a scalar condition value', async () => {
    installFetch({ triggers: [webhookTrigger({ filter_predicate: { branch: 'main' } })] });

    renderPage(<TriggersTab {...baseProps()} />);

    expect(await screen.findByText('verification: none · when branch eq main')).toBeInTheDocument();
  });

  it('renders a webhook trigger with no conditions as just the verification base', async () => {
    installFetch({ triggers: [webhookTrigger({ filter_predicate: {} })] });

    renderPage(<TriggersTab {...baseProps()} />);

    expect(await screen.findByText('verification: none')).toBeInTheDocument();
  });

  it('renders an unknown trigger kind with the raw event type badge and webhook-style title', async () => {
    installFetch({ triggers: [{ id: 9, kind: 'custom', event_type: 'CUSTOM.EVENT', filter_predicate: {} }] });

    renderPage(<TriggersTab {...baseProps()} />);

    // Unknown kind: no TG_EVENTS entry -> raw event_type; triggerTitle falls through to webhook copy.
    expect(await screen.findByText('CUSTOM.EVENT')).toBeInTheDocument();
    expect(screen.getByText('Incoming webhook')).toBeInTheDocument();
  });

  it('renders a mixed list of trigger kinds plus the Add-a-trigger tile', async () => {
    installFetch({ triggers: [columnTrigger(), scheduleTrigger(), slackTrigger(), webhookTrigger()] });

    renderPage(<TriggersTab {...baseProps()} />);

    expect(await screen.findByText('Task enters "Backlog"')).toBeInTheDocument();
    expect(screen.getByText('Every minute')).toBeInTheDocument();
    expect(screen.getByText('Slack message contains "ship"')).toBeInTheDocument();
    expect(screen.getByText('Incoming webhook')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Add a trigger/ })).toBeInTheDocument();
  });

  it('hides row actions and the Add-a-trigger tile when read-only', async () => {
    installFetch({ triggers: [columnTrigger()] });

    renderPage(<TriggersTab {...baseProps({ readOnly: true })} />);

    expect(await screen.findByText('Task enters "Backlog"')).toBeInTheDocument();
    expect(screen.queryByRole('switch')).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Add a trigger/ })).not.toBeInTheDocument();
  });

  it('deletes a column trigger and issues DELETE carrying the column kind param', async () => {
    const fetchSpy = installFetch({ triggers: [columnTrigger({ id: 1 })] });

    renderPage(<TriggersTab {...baseProps()} />);
    await screen.findByText('Task enters "Backlog"');

    // [edit, delete, add-tile] -> delete is index 1.
    const buttons = rowButtons();
    expect(buttons).toHaveLength(3);
    await userEvent.click(buttons[1]);

    await waitFor(() => expect(screen.queryByText('Task enters "Backlog"')).not.toBeInTheDocument());
    expect(fetchSpy).toHaveBeenCalledWith(
      '/api/v1/projects/7/workflows/3/triggers/1?kind=column',
      expect.objectContaining({ method: 'DELETE' }),
    );
  });

  it('keeps the row and logs an error when a delete request fails', async () => {
    const fetchSpy = installFetch({ triggers: [slackTrigger({ id: 2 })], deleteOk: false });

    renderPage(<TriggersTab {...baseProps()} />);
    await screen.findByText('Slack message contains "ship"');

    await userEvent.click(rowButtons()[1]);

    await waitFor(() => expect(consoleErrorSpy).toHaveBeenCalled());
    // Row survives a failed delete; a non-column trigger DELETEs without the kind query param.
    expect(screen.getByText('Slack message contains "ship"')).toBeInTheDocument();
    expect(fetchSpy).toHaveBeenCalledWith(
      '/api/v1/projects/7/workflows/3/triggers/2',
      expect.objectContaining({ method: 'DELETE' }),
    );
  });

  it('keeps the row and logs an error when a delete request throws', async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementation((_input, init) =>
      init?.method === 'DELETE'
        ? Promise.reject(new Error('network'))
        : Promise.resolve(json({ triggers: [slackTrigger({ id: 2 })] })),
    );

    renderPage(<TriggersTab {...baseProps()} />);
    await screen.findByText('Slack message contains "ship"');

    await userEvent.click(rowButtons()[1]);

    await waitFor(() => expect(consoleErrorSpy).toHaveBeenCalled());
    expect(screen.getByText('Slack message contains "ship"')).toBeInTheDocument();
  });

  it('toggles a trigger off and PATCHes enabled:false (no kind param for non-column)', async () => {
    const fetchSpy = installFetch({ triggers: [slackTrigger({ id: 2, enabled: true })] });

    renderPage(<TriggersTab {...baseProps()} />);
    await screen.findByText('Slack message contains "ship"');

    const toggle = screen.getByRole('switch');
    expect(toggle).toBeChecked();
    await userEvent.click(toggle);

    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        '/api/v1/projects/7/workflows/3/triggers/2',
        expect.objectContaining({ method: 'PATCH' }),
      ),
    );
    expect(callBody(fetchSpy, 'PATCH')).toEqual({ trigger: { enabled: false } });
    await waitFor(() => expect(screen.getByRole('switch')).not.toBeChecked());
  });

  it('PATCHes a column toggle with the column kind param', async () => {
    const fetchSpy = installFetch({ triggers: [columnTrigger({ id: 1, enabled: true })] });

    renderPage(<TriggersTab {...baseProps()} />);
    await screen.findByText('Task enters "Backlog"');

    await userEvent.click(screen.getByRole('switch'));

    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        '/api/v1/projects/7/workflows/3/triggers/1?kind=column',
        expect.objectContaining({ method: 'PATCH' }),
      ),
    );
  });

  it('reverts the switch and logs an error when a toggle request fails', async () => {
    installFetch({ triggers: [slackTrigger({ id: 2, enabled: true })], patchOk: false });

    renderPage(<TriggersTab {...baseProps()} />);
    await screen.findByText('Slack message contains "ship"');

    await userEvent.click(screen.getByRole('switch'));

    await waitFor(() => expect(consoleErrorSpy).toHaveBeenCalled());
    // Failure reverts the optimistic change, so the switch remains checked.
    expect(screen.getByRole('switch')).toBeChecked();
  });

  it('reverts the switch and logs an error when a toggle request throws', async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementation((_input, init) =>
      init?.method === 'PATCH'
        ? Promise.reject(new Error('network'))
        : Promise.resolve(json({ triggers: [slackTrigger({ id: 2, enabled: true })] })),
    );

    renderPage(<TriggersTab {...baseProps()} />);
    await screen.findByText('Slack message contains "ship"');

    await userEvent.click(screen.getByRole('switch'));

    await waitFor(() => expect(consoleErrorSpy).toHaveBeenCalled());
    expect(screen.getByRole('switch')).toBeChecked();
  });

  it('opens the add panel with column defaults from the Add-a-trigger tile', async () => {
    installFetch({ triggers: [columnTrigger()] });

    renderPage(<TriggersTab {...baseProps()} />);
    await screen.findByText('Task enters "Backlog"');

    await userEvent.click(screen.getByRole('button', { name: /Add a trigger/ }));

    // The TriggerFormPanel (create mode, default kind "column") mounts.
    expect(await screen.findByText('Trigger type')).toBeInTheDocument();
    expect(screen.getByText('Mode')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add trigger' })).toBeInTheDocument();
  });

  it('opens the add panel with the chosen kind from an empty-state choice', async () => {
    installFetch({ triggers: [] });

    renderPage(<TriggersTab {...baseProps()} />);
    await screen.findByText('Add your first trigger');

    await userEvent.click(screen.getByText('On schedule'));

    // openAdd('schedule') -> the schedule form fields render.
    expect(await screen.findByText('Cron')).toBeInTheDocument();
    expect(screen.getByText(/Runs:/)).toBeInTheDocument();
  });

  it('opens the edit panel locked to the trigger kind', async () => {
    installFetch({ triggers: [slackTrigger()] });

    renderPage(<TriggersTab {...baseProps()} />);
    await screen.findByText('Slack message contains "ship"');

    // [edit, delete, add-tile] -> edit is index 0.
    await userEvent.click(rowButtons()[0]);

    expect(await screen.findByText('Edit trigger')).toBeInTheDocument();
    expect(screen.getByText('Type is locked when editing')).toBeInTheDocument();
    expect(screen.getByText('Slack message')).toBeInTheDocument();
  });

  it('closes the panel via Cancel', async () => {
    installFetch({ triggers: [columnTrigger()] });

    renderPage(<TriggersTab {...baseProps()} />);
    await screen.findByText('Task enters "Backlog"');

    await userEvent.click(screen.getByRole('button', { name: /Add a trigger/ }));
    expect(await screen.findByText('Trigger type')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    await waitFor(() => expect(screen.queryByText('Trigger type')).not.toBeInTheDocument());
  });

  it('reloads the trigger list after the panel reports a successful save', async () => {
    const fetchSpy = installFetch({ triggers: [] });

    renderPage(<TriggersTab {...baseProps()} />);
    await screen.findByText('Add your first trigger');
    const getsBefore = getCallCount(fetchSpy);

    // Open the create panel from an empty-state choice, then submit.
    await userEvent.click(screen.getByText('Task enters column'));
    await userEvent.click(await screen.findByRole('button', { name: 'Add trigger' }));

    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        '/api/v1/projects/7/workflows/3/triggers',
        expect.objectContaining({ method: 'POST' }),
      ),
    );
    // onSaved() closes the panel and re-loads the list (a second GET).
    await waitFor(() => expect(screen.queryByText('Trigger type')).not.toBeInTheDocument());
    await waitFor(() => expect(getCallCount(fetchSpy)).toBeGreaterThan(getsBefore));
  });
});
