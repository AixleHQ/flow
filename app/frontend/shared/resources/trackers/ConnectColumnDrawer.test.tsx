import '@testing-library/jest-dom/vitest';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { buildProjectTracker } from 'test/factories/projectTracker';
import { renderPage, screen, userEvent, waitFor } from 'test/renderPage';

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

    await userEvent.click(screen.getByRole('combobox', { name: 'Column' }));
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
});
