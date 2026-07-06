import '@testing-library/jest-dom/vitest';
import type { ComponentProps } from 'react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent, waitFor } from 'test/renderPage';

import { WorkflowTriggersDrawer } from './WorkflowTriggersDrawer';

type DrawerProps = ComponentProps<typeof WorkflowTriggersDrawer>;

// The component takes plain props (no usePage read) and talks to the backend through apiFetch(),
// which is a thin wrapper over the global fetch() the test setup stubs. Each test that asserts a
// request (or needs seeded triggers) spies on fetch() and dispatches by HTTP method.

// ColumnOption / Trigger are the component's own local interfaces (no Typelizer type, so no factory
// exists); these literals match those interfaces exactly, mirroring how BuilderPage.test.tsx inlines
// its Step/Workflow fixtures.
const columns: DrawerProps['columns'] = [
  { id: 1, name: 'Backlog' },
  { id: 2, name: 'In Progress', boundWorkflowName: 'Other Flow' },
];

const baseProps = (overrides: Partial<DrawerProps> = {}): DrawerProps => ({
  opened: true,
  onClose: vi.fn(),
  projectId: 7,
  workflowId: 3,
  columns,
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
  ...o,
});

const slackTrigger = (o: Record<string, unknown> = {}) => ({
  id: 2,
  kind: 'slack',
  event_type: 'slack.message',
  filter_predicate: { channel: 'C1', text: { op: 'contains', value: 'ship' } },
  subject_policy: 'none',
  enabled: true,
  ...o,
});

const scheduleTrigger = (o: Record<string, unknown> = {}) => ({
  id: 3,
  kind: 'schedule',
  event_type: 'schedule.tick',
  schedule_config: { cron: '0 9 * * 1-5', timezone: 'UTC' },
  subject_policy: 'none',
  ...o,
});

const json = (body: unknown, status = 200): Response =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

// Install a fetch spy that returns `triggers` for the GET (load) and lets each mutating verb resolve
// to a controllable response. The default global stub (setup.ts) already returns `{}` (empty list).
function installFetch(opts: { triggers?: unknown[]; deleteOk?: boolean; postBody?: unknown } = {}) {
  const { triggers = [], deleteOk = true, postBody = {} } = opts;
  return vi.spyOn(globalThis, 'fetch').mockImplementation((_input, init) => {
    const method = init?.method;
    if (method === 'DELETE') return Promise.resolve(json({}, deleteOk ? 200 : 500));
    if (method === 'POST') return Promise.resolve(json(postBody));
    if (method === 'PATCH') return Promise.resolve(json({}));
    return Promise.resolve(json({ triggers }));
  });
}

const postCallBody = (spy: ReturnType<typeof installFetch>, method: string) => {
  const call = spy.mock.calls.find((c) => (c[1] as RequestInit | undefined)?.method === method);
  if (!call) throw new Error(`no ${method} call recorded`);
  return JSON.parse((call[1] as RequestInit).body as string);
};

afterEach(() => {
  vi.restoreAllMocks();
});

describe('Projects/Workflows/WorkflowTriggersDrawer', () => {
  it('renders nothing when the drawer is closed', () => {
    renderPage(<WorkflowTriggersDrawer {...baseProps({ opened: false })} />);

    expect(screen.queryByText(/how this workflow launches/)).not.toBeInTheDocument();
  });

  it('shows the empty state and an Add trigger button when there are no triggers', async () => {
    renderPage(<WorkflowTriggersDrawer {...baseProps()} />);

    expect(await screen.findByText('No triggers yet.')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add trigger' })).toBeInTheDocument();
  });

  it('renders a column trigger row with its kind label, event badge, and summary', async () => {
    installFetch({ triggers: [columnTrigger()] });

    renderPage(<WorkflowTriggersDrawer {...baseProps()} />);

    expect(await screen.findByText('Task enters column')).toBeInTheDocument();
    expect(screen.getByText('task.entered_column')).toBeInTheDocument();
    // triggerSummary(column) => "Backlog · auto · cooldown 5s"
    expect(screen.getByText('Backlog · auto · cooldown 5s')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Edit trigger' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Remove trigger' })).toBeInTheDocument();
  });

  it('summarizes a schedule trigger with its cron, timezone, and subject policy', async () => {
    installFetch({ triggers: [scheduleTrigger()] });

    renderPage(<WorkflowTriggersDrawer {...baseProps()} />);

    // triggerSummary(schedule) => "<cron> · <tz> · subject: <policy>"
    expect(await screen.findByText('0 9 * * 1-5 · UTC · subject: none')).toBeInTheDocument();
  });

  it('removes a trigger and issues a DELETE carrying the column kind param', async () => {
    const fetchSpy = installFetch({ triggers: [columnTrigger({ id: 1 })] });

    renderPage(<WorkflowTriggersDrawer {...baseProps()} />);

    await userEvent.click(await screen.findByRole('button', { name: 'Remove trigger' }));

    // On a successful DELETE the row is filtered out of local state.
    await waitFor(() => expect(screen.queryByText('Task enters column')).not.toBeInTheDocument());
    expect(fetchSpy).toHaveBeenCalledWith(
      '/api/v1/projects/7/workflows/3/triggers/1?kind=column',
      expect.objectContaining({ method: 'DELETE' }),
    );
  });

  it('keeps the trigger and shows an error notification when removal fails', async () => {
    const fetchSpy = installFetch({ triggers: [slackTrigger({ id: 2 })], deleteOk: false });

    renderPage(<WorkflowTriggersDrawer {...baseProps()} />);

    await userEvent.click(await screen.findByRole('button', { name: 'Remove trigger' }));

    expect(await screen.findByText('Failed to remove trigger')).toBeInTheDocument();
    // Row survives a failed delete; a non-column trigger deletes without the kind query param.
    expect(screen.getByText('Slack message')).toBeInTheDocument();
    expect(fetchSpy).toHaveBeenCalledWith(
      '/api/v1/projects/7/workflows/3/triggers/2',
      expect.objectContaining({ method: 'DELETE' }),
    );
  });

  it('opens the create form with the kind selector when Add trigger is clicked', async () => {
    renderPage(<WorkflowTriggersDrawer {...baseProps()} />);

    await userEvent.click(await screen.findByRole('button', { name: 'Add trigger' }));

    // The AddTriggerForm (create mode) exposes the kind SegmentedControl + a Cancel action.
    expect(screen.getByText('Webhook')).toBeInTheDocument();
    expect(screen.getByText('Schedule')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Cancel' })).toBeInTheDocument();
  });

  it('posts a column trigger with the default column, mode, and cooldown', async () => {
    const fetchSpy = installFetch({ triggers: [] });

    renderPage(<WorkflowTriggersDrawer {...baseProps()} />);

    await userEvent.click(await screen.findByRole('button', { name: 'Add trigger' }));
    // Second "Add trigger" is now the form's submit button (the opener was replaced by the form).
    await userEvent.click(screen.getByRole('button', { name: 'Add trigger' }));

    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        '/api/v1/projects/7/workflows/3/triggers',
        expect.objectContaining({ method: 'POST' }),
      ),
    );
    // columns[0] (Backlog, unbound) is the default; mode/cooldown carry their initial values.
    expect(postCallBody(fetchSpy, 'POST')).toEqual({
      trigger: { kind: 'column', board_column_id: '1', trigger_mode: 'auto', cooldown_seconds: 5 },
    });
  });

  it('disables submit and flags an invalid cron on the schedule form', async () => {
    installFetch({ triggers: [] });

    renderPage(<WorkflowTriggersDrawer {...baseProps()} />);

    await userEvent.click(await screen.findByRole('button', { name: 'Add trigger' }));
    await userEvent.click(screen.getByText('Schedule'));

    // The default cron is valid, so a human-readable description is shown and submit is enabled.
    expect(screen.getByText(/Runs:/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add trigger' })).toBeEnabled();

    const cronInput = screen.getByRole('textbox', { name: 'Cron' });
    await userEvent.clear(cronInput);
    await userEvent.type(cronInput, 'zzz');

    expect(await screen.findByText('Not a valid cron expression')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add trigger' })).toBeDisabled();
  });

  it('reveals the task column and title template when the subject is set to Create a task', async () => {
    installFetch({ triggers: [] });

    renderPage(<WorkflowTriggersDrawer {...baseProps()} />);

    await userEvent.click(await screen.findByRole('button', { name: 'Add trigger' }));
    await userEvent.click(screen.getByText('Slack'));

    // Open the subject Select and choose "Create a task". Mantine renders a Select as several
    // label-associated nodes (visible combobox input + hidden input), so getByLabelText matches
    // multiple and throws; query the combobox by its accessible name instead (RTL role priority).
    await userEvent.click(screen.getByRole('combobox', { name: /Subject/ }));
    await userEvent.click(await screen.findByRole('option', { name: 'Create a task' }));

    expect(await screen.findByText('Task column')).toBeInTheDocument();
    expect(screen.getByText('The task body is filled with the triggering payload automatically.')).toBeInTheDocument();
  });

  it('shows the webhook created panel with the request URL after a webhook trigger is created', async () => {
    const fetchSpy = installFetch({
      triggers: [],
      postBody: { webhook_url: 'https://example.test/hooks/abc', webhook_secret: 'sek_123' },
    });

    renderPage(<WorkflowTriggersDrawer {...baseProps()} />);

    await userEvent.click(await screen.findByRole('button', { name: 'Add trigger' }));
    await userEvent.click(screen.getByText('Webhook'));
    await userEvent.click(screen.getByRole('button', { name: 'Add trigger' }));

    expect(await screen.findByText('Webhook trigger created')).toBeInTheDocument();
    expect(screen.getByText('https://example.test/hooks/abc')).toBeInTheDocument();
    expect(screen.getByText('Request URL')).toBeInTheDocument();
    expect(screen.getByText('Secret')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Done' })).toBeInTheDocument();
    // A brand-new webhook posts its (immutable) verification strategy and an empty filter.
    expect(postCallBody(fetchSpy, 'POST').trigger).toEqual({
      kind: 'webhook',
      verification_strategy: 'none',
      filter_predicate: {},
      subject_policy: 'none',
    });
  });

  it('cancelling the create form returns to the Add trigger button', async () => {
    renderPage(<WorkflowTriggersDrawer {...baseProps()} />);

    await userEvent.click(await screen.findByRole('button', { name: 'Add trigger' }));
    expect(screen.getByRole('button', { name: 'Cancel' })).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));

    await waitFor(() => expect(screen.queryByRole('button', { name: 'Cancel' })).not.toBeInTheDocument());
    expect(screen.getByRole('button', { name: 'Add trigger' })).toBeInTheDocument();
  });

  it('opens the edit form seeded from the slack trigger predicate', async () => {
    installFetch({ triggers: [slackTrigger()] });

    renderPage(<WorkflowTriggersDrawer {...baseProps()} />);

    await userEvent.click(await screen.findByRole('button', { name: 'Edit trigger' }));

    expect(screen.getByText('Edit slack message trigger')).toBeInTheDocument();
    // Channel is recovered from filter_predicate.channel, and the enabled switch reflects the trigger.
    expect(screen.getByRole('textbox', { name: 'Channel id' })).toHaveValue('C1');
    expect(screen.getByRole('switch', { name: 'Enabled' })).toBeChecked();
  });

  it('patches the trigger when the edit form is saved', async () => {
    const fetchSpy = installFetch({ triggers: [slackTrigger({ id: 2 })] });

    renderPage(<WorkflowTriggersDrawer {...baseProps()} />);

    await userEvent.click(await screen.findByRole('button', { name: 'Edit trigger' }));
    await userEvent.click(screen.getByRole('button', { name: 'Save' }));

    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        '/api/v1/projects/7/workflows/3/triggers/2',
        expect.objectContaining({ method: 'PATCH' }),
      ),
    );
    const body = postCallBody(fetchSpy, 'PATCH');
    expect(body.trigger.filter_predicate.channel).toBe('C1');
    expect(body.trigger.enabled).toBe(true);
  });
});
