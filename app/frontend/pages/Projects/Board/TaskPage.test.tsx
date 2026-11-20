import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { buildBoardColumn } from 'test/factories/boardColumn';
import { buildBoardTask } from 'test/factories/boardTask';
import { answerFetch } from 'test/fetchStub';
import { renderAuthedPage, screen, userEvent, waitFor, within } from 'test/renderPage';
import type BoardTask from 'types/generated/BoardTask';

import TaskPage from './TaskPage';

const project = { id: 7, name: 'Falcon Initiative' };

const pageProps = (task: Partial<BoardTask> = {}) => ({
  project,
  selectedTask: buildBoardTask({
    id: 3,
    number: 27,
    title: 'Performance evaluations: add statuses',
    description: '## Background\n\nRequest from Slack.',
    boardColumnId: 100,
    ...task,
  }),
  columns: [buildBoardColumn({ id: 100, name: 'Backlog', position: 0 })],
  members: [],
  taskComments: [],
  taskAssets: [],
  taskActivities: [],
  taskWorkflowRuns: [],
});

describe('Projects/Board/TaskPage', () => {
  beforeEach(() => vi.mocked(router.visit).mockClear());

  it('shows the whole task with a way back to the board, and no drawer controls', () => {
    renderAuthedPage(<TaskPage />, { props: pageProps() });

    expect(screen.getByText('Performance evaluations: add statuses')).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Background' })).toBeInTheDocument();
    expect(screen.getByRole('combobox', { name: 'Column' })).toHaveValue('Backlog');
    expect(screen.getByRole('link', { name: 'Tasks' })).toHaveAttribute('href', '/company/projects/7/board');
    expect(screen.queryByRole('button', { name: 'Close' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Expand' })).not.toBeInTheDocument();
    expect(screen.queryByRole('link', { name: 'Open as page' })).not.toBeInTheDocument();
  });

  it('copies the link to this page', async () => {
    const user = userEvent.setup();
    renderAuthedPage(<TaskPage />, { props: pageProps() });

    await user.click(screen.getByRole('button', { name: 'Copy link to task' }));

    expect(await navigator.clipboard.readText()).toBe(`${window.location.origin}/company/projects/7/tasks/27`);
  });

  it('says when the task is archived', () => {
    renderAuthedPage(<TaskPage />, { props: pageProps({ archived: true }) });

    expect(screen.getByText('Archived')).toBeInTheDocument();
  });

  it('returns to the board once the task is deleted', async () => {
    const fetchSpy = answerFetch({ 'DELETE /api/v1/projects/7/tasks/3': {} });
    renderAuthedPage(<TaskPage />, { props: pageProps() });

    await userEvent.click(screen.getByRole('button', { name: 'Delete' }));
    await userEvent.click(within(await screen.findByRole('dialog')).getByRole('button', { name: 'Delete' }));

    await waitFor(() => expect(router.visit).toHaveBeenCalledWith('/company/projects/7/board'));
    fetchSpy.mockRestore();
  });
});
