import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { fireEvent } from '@testing-library/react';
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

  describe('assets tab upload', () => {
    const file = (name: string) => new File(['x'], name, { type: 'text/plain' });
    const postedNames = (spy: ReturnType<typeof answerFetch>) =>
      spy.mock.calls.map(([, init]) => (init?.body as FormData).get('task_asset[name]')).sort();

    const openAssets = async (props: Record<string, unknown> = {}) => {
      const user = userEvent.setup();
      renderAuthedPage(<TaskPage />, { props: { ...pageProps(), ...props } });
      await user.click(screen.getByRole('tab', { name: /Assets/ }));
      return user;
    };

    beforeEach(() => vi.mocked(router.reload).mockClear());

    it('attaches every dropped file and reloads once', async () => {
      const fetchSpy = answerFetch({ 'POST /api/v1/projects/7/tasks/3/assets': {} });
      await openAssets();

      fireEvent.drop(screen.getByText('Click to select files or drag & drop'), {
        dataTransfer: { files: [file('a.txt'), file('b.txt'), file('c.txt')] },
      });

      await waitFor(() => expect(router.reload).toHaveBeenCalledTimes(1));
      expect(postedNames(fetchSpy)).toEqual(['a.txt', 'b.txt', 'c.txt']);
    });

    it('attaches every file chosen with Upload new', async () => {
      const fetchSpy = answerFetch({ 'POST /api/v1/projects/7/tasks/3/assets': {} });
      const user = await openAssets();

      const input = screen.getByLabelText('Upload files');
      expect(input).toHaveAttribute('multiple');
      await user.upload(input, [file('a.txt'), file('b.txt')]);

      await waitFor(() => expect(router.reload).toHaveBeenCalledTimes(1));
      expect(postedNames(fetchSpy)).toEqual(['a.txt', 'b.txt']);
    });

    it('still uploads a single file', async () => {
      const fetchSpy = answerFetch({ 'POST /api/v1/projects/7/tasks/3/assets': {} });
      await openAssets();

      fireEvent.drop(screen.getByText('Click to select files or drag & drop'), {
        dataTransfer: { files: [file('only.txt')] },
      });

      await waitFor(() => expect(router.reload).toHaveBeenCalledTimes(1));
      expect(postedNames(fetchSpy)).toEqual(['only.txt']);
    });

    it('reports failed files and still reloads', async () => {
      answerFetch({
        'POST /api/v1/projects/7/tasks/3/assets': (init?: RequestInit) =>
          (init?.body as FormData).get('task_asset[name]') === 'bad.txt'
            ? new Response(JSON.stringify({ error: 'File is too large' }), {
                status: 422,
                headers: { 'Content-Type': 'application/json' },
              })
            : {},
      });
      await openAssets();

      fireEvent.drop(screen.getByText('Click to select files or drag & drop'), {
        dataTransfer: { files: [file('a.txt'), file('bad.txt')] },
      });

      expect(await screen.findByText('1 of 2 files failed to upload')).toBeInTheDocument();
      expect(router.reload).toHaveBeenCalledTimes(1);
    });

    it('hides the drop zone without execute permission', async () => {
      await openAssets({ projectPermissions: { canExecute: false, canManage: false } });

      expect(screen.queryByText('Click to select files or drag & drop')).not.toBeInTheDocument();
    });
  });
});
