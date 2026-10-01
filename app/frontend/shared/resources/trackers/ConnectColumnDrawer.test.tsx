import '@testing-library/jest-dom/vitest';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { buildProjectTracker } from 'test/factories/projectTracker';
import { renderPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import { ConnectColumnDrawer } from './ConnectColumnDrawer';

const json = (body: unknown, status = 200): Response =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

const workflows = [
  { id: 3, name: 'Intake' },
  { id: 4, name: 'Review' },
];
const boardColumns = [{ id: 9, name: 'Inbox' }];

afterEach(() => {
  vi.restoreAllMocks();
});

describe('ConnectColumnDrawer', () => {
  it("offers the tracker's own columns and wires an ordinary tracker trigger to the chosen workflow", async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockImplementation((_input, init) =>
        Promise.resolve(
          init?.method === 'POST'
            ? json({ id: 1 }, 201)
            : json({ statuses: [{ name: 'Ready for AI', category: 'todo' }] }),
        ),
      );
    const onClose = vi.fn();
    renderPage(
      <ConnectColumnDrawer
        projectId={7}
        tracker={buildProjectTracker()}
        workflows={workflows}
        boardColumns={boardColumns}
        onClose={onClose}
      />,
    );

    const column = screen.getByRole('combobox', { name: 'Column' });
    await waitFor(() => expect(column).toBeEnabled());
    await userEvent.click(column);
    await userEvent.click(await screen.findByRole('option', { name: 'Ready for AI' }));
    await userEvent.click(screen.getByRole('button', { name: 'Connect' }));

    await waitFor(() => expect(onClose).toHaveBeenCalled());
    const post = fetchSpy.mock.calls.find((c) => (c[1] as RequestInit | undefined)?.method === 'POST');
    expect(post?.[0]).toBe('/api/v1/projects/7/workflows/3/triggers');
    expect(JSON.parse((post?.[1] as RequestInit).body as string).trigger).toEqual({
      kind: 'tracker',
      event_type: 'tracker.issue.status_changed',
      filter_predicate: { 'change.to.name': { op: 'in', value: ['Ready for AI'] } },
      project_tracker_id: 5,
      subject_policy: 'find_or_create_task',
      subject_column_id: '9',
      aixle_changes: 'ignore',
    });
  });

  it("falls back to a typed column, and warns that it is not checked, when the board's columns cannot be read", async () => {
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockImplementation((_input, init) =>
        Promise.resolve(init?.method === 'POST' ? json({ id: 1 }, 201) : json({ error: 'Forbidden' }, 422)),
      );
    renderPage(
      <ConnectColumnDrawer
        projectId={7}
        tracker={buildProjectTracker()}
        workflows={workflows}
        boardColumns={boardColumns}
        onClose={vi.fn()}
      />,
    );

    const column = await screen.findByRole('textbox', { name: 'Column' });
    expect(screen.getByText(/could not read the columns of the tracker's board/)).toBeInTheDocument();
    await userEvent.type(column, 'Ready for AI');
    await userEvent.click(screen.getByRole('button', { name: 'Connect' }));

    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({ method: 'POST' })),
    );
    const post = fetchSpy.mock.calls.find((c) => (c[1] as RequestInit | undefined)?.method === 'POST');
    expect(JSON.parse((post?.[1] as RequestInit).body as string).trigger.filter_predicate).toEqual({
      'change.to.name': { op: 'in', value: ['Ready for AI'] },
    });
  });

  it('does not offer a mention where Aixle cannot recognise one, and says why', async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(() => Promise.resolve(json({ statuses: [] })));
    renderPage(
      <ConnectColumnDrawer
        projectId={7}
        tracker={buildProjectTracker({ provider: 'jira', mentionsRecognized: false })}
        workflows={workflows}
        boardColumns={boardColumns}
        onClose={vi.fn()}
      />,
    );

    expect(screen.getByText(/This Jira connection acts as a person/)).toBeInTheDocument();
    await userEvent.click(screen.getByRole('combobox', { name: 'Start a workflow when' }));
    expect(await screen.findByRole('option', { name: 'Aixle is mentioned in a comment' })).toHaveAttribute(
      'data-combobox-disabled',
    );
  });

  it('shows why the server refused, such as a workflow that cannot run unattended', async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementation((_input, init) =>
      Promise.resolve(
        init?.method === 'POST' ? json({ errors: ["Workflow can't run unattended"] }, 422) : json({ statuses: [] }),
      ),
    );
    renderPage(
      <ConnectColumnDrawer
        projectId={7}
        tracker={buildProjectTracker()}
        workflows={workflows}
        boardColumns={boardColumns}
        onClose={vi.fn()}
      />,
    );

    await userEvent.click(screen.getByRole('combobox', { name: 'Start a workflow when' }));
    await userEvent.click(await screen.findByRole('option', { name: 'Aixle is mentioned in a comment' }));
    await userEvent.click(screen.getByRole('button', { name: 'Connect' }));

    expect(await screen.findByText("Workflow can't run unattended")).toBeInTheDocument();
  });

  it('closes without asking while only the defaults are chosen', async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(() =>
      Promise.resolve(json({ statuses: [{ name: 'Ready for AI', category: 'todo' }] })),
    );
    const onClose = vi.fn();
    renderPage(
      <ConnectColumnDrawer
        projectId={7}
        tracker={buildProjectTracker()}
        workflows={workflows}
        boardColumns={boardColumns}
        onClose={onClose}
      />,
    );

    expect(screen.getByRole('combobox', { name: 'Workflow' })).toHaveValue('Intake');
    await userEvent.click(screen.getByRole('button', { name: 'Close' }));

    expect(onClose).toHaveBeenCalledTimes(1);
    expect(screen.queryByRole('dialog', { name: 'Discard unsaved changes?' })).not.toBeInTheDocument();
  });

  it('asks before closing over a changed choice, and closes once the user discards', async () => {
    vi.spyOn(globalThis, 'fetch').mockImplementation(() =>
      Promise.resolve(json({ statuses: [{ name: 'Ready for AI', category: 'todo' }] })),
    );
    const onClose = vi.fn();
    renderPage(
      <ConnectColumnDrawer
        projectId={7}
        tracker={buildProjectTracker()}
        workflows={workflows}
        boardColumns={boardColumns}
        onClose={onClose}
      />,
    );

    await userEvent.click(screen.getByRole('combobox', { name: 'Workflow' }));
    await userEvent.click(await screen.findByRole('option', { name: 'Review' }));
    await userEvent.click(screen.getByRole('button', { name: 'Close' }));

    const discard = await screen.findByRole('dialog', { name: 'Discard unsaved changes?' });
    expect(onClose).not.toHaveBeenCalled();
    await userEvent.click(within(discard).getByRole('button', { name: 'Discard' }));
    expect(onClose).toHaveBeenCalledTimes(1);
  });
});
