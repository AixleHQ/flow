import '@testing-library/jest-dom/vitest';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import { TriggersContent } from './TriggersContent';
import type { Trigger } from './types';

// Trigger is a local interface (no Typelizer type, so no factory exists); these literals match it.
const workflows = [
  { id: 3, name: 'Intake' },
  { id: 4, name: 'Release' },
];

const triggers: Trigger[] = [
  {
    id: 1,
    kind: 'column',
    source: 'board',
    event_type: 'board.column_changed',
    column_name: 'Backlog',
    trigger_mode: 'auto',
    cooldown_seconds: 5,
    enabled: true,
    workflow_id: 3,
    workflow_name: 'Intake',
    created_by: { id: 1, name: 'Ida Ferris' },
  },
  {
    id: 2,
    kind: 'slack',
    source: 'chat',
    chat_provider: 'slack',
    event_type: 'slack.message',
    filter_predicate: { text: { op: 'contains', value: 'ship' } },
    enabled: true,
    workflow_id: 4,
    workflow_name: 'Release',
    created_by: { id: 1, name: 'Ida Ferris' },
  },
  {
    id: 2,
    kind: 'webhook',
    source: 'webhook',
    event_type: 'webhook.abc',
    filter_predicate: {},
    verification_strategy: 'shared_token',
    enabled: false,
    workflow_id: 4,
    workflow_name: 'Release',
    created_by: null,
  },
];

const json = (body: unknown, status = 200): Response =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

function installFetch(list: Trigger[] = triggers, opts: { patchOk?: boolean } = {}) {
  return vi.spyOn(globalThis, 'fetch').mockImplementation((_input, init) => {
    if (init?.method === 'DELETE') return Promise.resolve(json({}));
    if (init?.method === 'PATCH') return Promise.resolve(json({}, opts.patchOk === false ? 422 : 200));
    return Promise.resolve(json({ triggers: list }));
  });
}

const render = (props: Record<string, unknown> = {}) =>
  renderPage(<TriggersContent projectId={7} workflows={workflows} columns={[]} trackers={[]} />, { props });

afterEach(() => {
  vi.restoreAllMocks();
});

describe('TriggersContent', () => {
  it('lists every trigger of the project with the workflow it starts', async () => {
    const fetchSpy = installFetch();
    render();

    const column = await screen.findByRole('article', { name: 'Task enters "Backlog"' });
    expect(fetchSpy).toHaveBeenCalledWith('/api/v1/projects/7/triggers', expect.anything());
    expect(within(column).getByRole('link', { name: 'Intake' })).toHaveAttribute(
      'href',
      '/company/projects/7/workflows/3/builder?tab=triggers',
    );
    const chat = screen.getByRole('article', { name: 'Slack message contains "ship"' });
    expect(within(chat).getByText('SLACK.MESSAGE')).toBeInTheDocument();
    expect(screen.getByText('verification: shared_token')).toBeInTheDocument();
    expect(screen.getByText(/A workflow can also be started by hand/)).toBeInTheDocument();
  });

  it('filters by source, chat messenger included, and by workflow', async () => {
    installFetch();
    render();
    await screen.findByRole('article', { name: 'Task enters "Backlog"' });

    await userEvent.click(screen.getByRole('textbox', { name: 'Filter by source' }));
    await userEvent.click(await screen.findByRole('option', { name: 'Chat · Slack' }));
    expect(screen.getAllByRole('article')).toHaveLength(1);
    expect(screen.getByText('1 of 3')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('textbox', { name: 'Filter by source' }));
    await userEvent.click(await screen.findByRole('option', { name: 'All sources' }));
    await userEvent.click(screen.getByRole('textbox', { name: 'Filter by workflow' }));
    await userEvent.click(await screen.findByRole('option', { name: 'Intake' }));
    expect(screen.getAllByRole('article').map((a) => a.getAttribute('aria-label'))).toEqual(['Task enters "Backlog"']);
  });

  it('switches a trigger off through its own workflow, and has no switch on a column trigger', async () => {
    const fetchSpy = installFetch();
    render();
    await screen.findByRole('article', { name: 'Task enters "Backlog"' });

    expect(screen.queryByRole('switch', { name: 'Enable Task enters "Backlog"' })).not.toBeInTheDocument();
    await userEvent.click(screen.getByRole('switch', { name: 'Enable Slack message contains "ship"' }));

    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        '/api/v1/projects/7/workflows/4/triggers/2',
        expect.objectContaining({ method: 'PATCH', body: JSON.stringify({ trigger: { enabled: false } }) }),
      ),
    );
    await waitFor(() =>
      expect(screen.getByRole('switch', { name: 'Enable Slack message contains "ship"' })).not.toBeChecked(),
    );
  });

  it('deletes a column trigger only after confirmation, with the column kind', async () => {
    const fetchSpy = installFetch();
    render();
    await screen.findByRole('article', { name: 'Task enters "Backlog"' });

    await userEvent.click(screen.getByRole('button', { name: 'Delete Task enters "Backlog"' }));
    expect(fetchSpy).not.toHaveBeenCalledWith(expect.anything(), expect.objectContaining({ method: 'DELETE' }));
    await userEvent.click(await screen.findByRole('button', { name: 'Delete' }));

    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        '/api/v1/projects/7/workflows/3/triggers/1?kind=column',
        expect.objectContaining({ method: 'DELETE' }),
      ),
    );
    await waitFor(() =>
      expect(screen.queryByRole('article', { name: 'Task enters "Backlog"' })).not.toBeInTheDocument(),
    );
  });

  it('opens the form with a workflow picker to add a trigger', async () => {
    installFetch();
    render();
    await screen.findByRole('article', { name: 'Task enters "Backlog"' });

    await userEvent.click(screen.getByRole('button', { name: 'Add trigger' }));

    expect(screen.getByRole('textbox', { name: 'Workflow' })).toBeInTheDocument();
  });

  it('hides every write control from a read-only viewer', async () => {
    installFetch();
    render({ projectPermissions: { canExecute: false, canManage: false } });
    await screen.findByRole('article', { name: 'Task enters "Backlog"' });

    expect(screen.queryByRole('button', { name: 'Add trigger' })).not.toBeInTheDocument();
    expect(screen.queryByRole('switch')).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /^Delete / })).not.toBeInTheDocument();
  });

  it('says so when the project has no trigger yet', async () => {
    installFetch([]);
    render();

    expect(await screen.findByText('No triggers')).toBeInTheDocument();
    expect(screen.getByText('Nothing starts a workflow of this project on its own yet.')).toBeInTheDocument();
  });
});
