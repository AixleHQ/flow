import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { buildBoardActivity } from 'test/factories/boardActivity';
import { answerFetch } from 'test/fetchStub';
import { renderPage, screen, userEvent } from 'test/renderPage';

import { TaskActivityEntry } from './TaskActivityEntry';

const detailPath = 'GET /api/v1/projects/7/tasks/1/activities/31';

describe('Projects/Board/TaskActivityEntry', () => {
  it('names the changed fields and shows their old and new values on request', async () => {
    const fetchSpy = answerFetch({
      [detailPath]: {
        changes: [
          { field: 'priority', label: 'Priority', before: 'High', after: null },
          { field: 'description', label: 'Description', before: 'First line', after: 'First line\nSecond line' },
        ],
      },
    });
    renderPage(
      <TaskActivityEntry
        activity={buildBoardActivity({ changedFields: ['Priority', 'Description'] })}
        projectId={7}
        taskId={1}
      />,
    );

    expect(fetchSpy).not.toHaveBeenCalled();
    await userEvent.click(screen.getByRole('button', { name: 'Show changes: Priority, Description' }));

    expect(await screen.findByText('Before')).toBeInTheDocument();
    expect(screen.getByText('High')).toBeInTheDocument();
    expect(screen.getByText('empty')).toBeInTheDocument();
    expect(screen.getByText('First line')).toBeInTheDocument();
    expect(screen.getByText(/Second line/)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Hide changes: Priority, Description' })).toHaveAttribute(
      'aria-expanded',
      'true',
    );
  });

  it('loads the changes once, however often it is opened', async () => {
    const fetchSpy = answerFetch({
      [detailPath]: { changes: [{ field: 'title', label: 'Title', before: 'Old', after: 'New' }] },
    });
    renderPage(
      <TaskActivityEntry activity={buildBoardActivity({ changedFields: ['Title'] })} projectId={7} taskId={1} />,
    );

    await userEvent.click(screen.getByRole('button', { name: 'Show changes: Title' }));
    expect(await screen.findByText('Old')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Hide changes: Title' }));
    await userEvent.click(screen.getByRole('button', { name: 'Show changes: Title' }));

    expect(screen.getByText('New')).toBeInTheDocument();
    expect(fetchSpy).toHaveBeenCalledTimes(1);
  });

  it('offers nothing to open for an entry without recorded changes', () => {
    renderPage(
      <TaskActivityEntry
        activity={buildBoardActivity({ eventType: 'comment_added', changedFields: [] })}
        projectId={7}
        taskId={1}
      />,
    );

    expect(screen.queryByRole('button')).not.toBeInTheDocument();
  });

  it('closes again and says so when the changes cannot be loaded', async () => {
    answerFetch({ [detailPath]: new Response(JSON.stringify({ error: 'Not found' }), { status: 404 }) });
    renderPage(
      <TaskActivityEntry activity={buildBoardActivity({ changedFields: ['Title'] })} projectId={7} taskId={1} />,
    );

    await userEvent.click(screen.getByRole('button', { name: 'Show changes: Title' }));

    expect(await screen.findByText('Not found')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Show changes: Title' })).toHaveAttribute('aria-expanded', 'false');
  });
});
