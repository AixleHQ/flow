import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { renderAuthedPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import BoardPage from './BoardPage';

const project = { id: 7, name: 'Falcon Initiative' };

const board = { id: 11, name: 'Project Board', presetOrigin: null };

const columns = [
  { id: 100, name: 'Backlog', position: 0, purpose: null, workflowBinding: null },
  { id: 200, name: 'In Progress', position: 1, purpose: null, workflowBinding: null },
];

const makeTask = (
  overrides: Partial<{ id: number; title: string; boardColumnId: number; position: number }> = {},
) => ({
  id: 1,
  title: 'Untitled',
  description: null,
  taskType: 'story',
  priority: null,
  assigneeId: null,
  assigneeName: null,
  boardColumnId: 100,
  position: 0,
  parentTaskId: null,
  tags: [],
  commentsCount: 0,
  childrenCount: 0,
  assetsCount: 0,
  recentWorkflowRuns: [],
  pendingWaits: [],
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  ...overrides,
});

const populatedProps = {
  project,
  board,
  columns,
  tasks: [
    makeTask({ id: 1, title: 'Wire up authentication', boardColumnId: 100, position: 0 }),
    makeTask({ id: 2, title: 'Render dashboard charts', boardColumnId: 200, position: 0 }),
  ],
  members: [{ id: 1, name: 'Dana Scout' }],
  workflows: [],
  viewPresets: [],
  currentUserId: 1,
};

describe('Projects/Board/BoardPage', () => {
  it('shows the preset picker empty state when the project has no board yet', () => {
    renderAuthedPage(<BoardPage />, {
      props: {
        project,
        board: null,
        boardPresets: [{ key: 'simple_kanban', displayName: 'Simple Kanban', columns: ['Todo', 'Doing', 'Done'] }],
        columns: [],
        tasks: [],
        members: [],
        workflows: [],
      },
    });

    expect(screen.getByText('Create your task board')).toBeInTheDocument();
    expect(screen.getByText('Simple Kanban')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Use this template' })).toBeInTheDocument();
  });

  it('renders the board columns with their task cards', () => {
    renderAuthedPage(<BoardPage />, { props: populatedProps });

    expect(screen.getByText('Backlog')).toBeInTheDocument();
    expect(screen.getByText('In Progress')).toBeInTheDocument();
    expect(screen.getByText('Wire up authentication')).toBeInTheDocument();
    expect(screen.getByText('Render dashboard charts')).toBeInTheDocument();
  });

  it('filters task cards by the search query', async () => {
    renderAuthedPage(<BoardPage />, { props: populatedProps });

    await userEvent.type(screen.getByPlaceholderText('Search title...'), 'dashboard');

    expect(screen.queryByText('Wire up authentication')).not.toBeInTheDocument();
    expect(screen.getByText('Render dashboard charts')).toBeInTheDocument();
  });

  it('renders an empty-column placeholder when a column has no tasks', () => {
    renderAuthedPage(<BoardPage />, {
      props: {
        ...populatedProps,
        // Only Backlog has a task; In Progress is empty → "No tasks yet" placeholder.
        tasks: [makeTask({ id: 1, title: 'Wire up authentication', boardColumnId: 100, position: 0 })],
      },
    });

    expect(screen.getByText('No tasks yet')).toBeInTheDocument();
  });

  it('opens the create-task modal via the "n" hotkey', async () => {
    renderAuthedPage(<BoardPage />, { props: populatedProps });

    await userEvent.keyboard('n');

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('New Task')).toBeInTheDocument();
    expect(within(dialog).getByRole('button', { name: 'Create' })).toBeInTheDocument();
  });

  // --- task card rendering branches ---

  it('renders the task-type badge, tags (with overflow) and comment count on a card', () => {
    renderAuthedPage(<BoardPage />, {
      props: {
        ...populatedProps,
        tasks: [
          {
            ...makeTask({ id: 1, title: 'Fix login crash', boardColumnId: 100 }),
            taskType: 'bug',
            priority: 'high',
            tags: ['frontend', 'auth', 'urgent', 'p0'],
            commentsCount: 3,
            assigneeName: 'Dana Scout',
          },
        ],
      },
    });

    // Scope to the card itself: the same tag strings also populate the toolbar's tag MultiSelect,
    // so query within the card Paper that holds the title.
    const card = screen.getByText('Fix login crash').closest('[class*="Paper-root"]') as HTMLElement;
    const inCard = within(card);

    expect(inCard.getByText('bug')).toBeInTheDocument();
    expect(inCard.getByText('frontend')).toBeInTheDocument();
    expect(inCard.getByText('auth')).toBeInTheDocument();
    expect(inCard.getByText('urgent')).toBeInTheDocument();
    // Only the first 3 tags render inline on the card; the 4th collapses into a "+1" overflow badge.
    expect(inCard.queryByText('p0')).not.toBeInTheDocument();
    expect(inCard.getByText('+1')).toBeInTheDocument();
    // commentsCount renders next to the message icon.
    expect(inCard.getByText('3')).toBeInTheDocument();
  });

  it('navigates to the task detail when a card is clicked', async () => {
    renderAuthedPage(<BoardPage />, { props: populatedProps });

    await userEvent.click(screen.getByText('Wire up authentication'));

    expect(router.get).toHaveBeenCalledWith(
      '/company/projects/7/board',
      { task: 1 },
      expect.objectContaining({ preserveState: true }),
    );
  });

  // --- toolbar filters ---

  it('filters by task type via the Type select and shows a Clear control', async () => {
    renderAuthedPage(<BoardPage />, {
      props: {
        ...populatedProps,
        tasks: [
          { ...makeTask({ id: 1, title: 'Fix login crash', boardColumnId: 100 }), taskType: 'bug' },
          { ...makeTask({ id: 2, title: 'Build settings page', boardColumnId: 200 }), taskType: 'story' },
        ],
      },
    });

    // Open the Type select (placeholder 'Type') and pick Bug.
    await userEvent.click(screen.getByPlaceholderText('Type'));
    await userEvent.click(await screen.findByRole('option', { name: 'Bug' }));

    expect(screen.getByText('Fix login crash')).toBeInTheDocument();
    expect(screen.queryByText('Build settings page')).not.toBeInTheDocument();

    // A Clear button appears once a filter is active; clicking it restores all tasks.
    const clear = screen.getByRole('button', { name: 'Clear' });
    await userEvent.click(clear);
    expect(screen.getByText('Build settings page')).toBeInTheDocument();
  });

  it('applies the built-in "All Bugs" view preset from the Presets menu', async () => {
    renderAuthedPage(<BoardPage />, {
      props: {
        ...populatedProps,
        tasks: [
          { ...makeTask({ id: 1, title: 'Fix login crash', boardColumnId: 100 }), taskType: 'bug' },
          { ...makeTask({ id: 2, title: 'Build settings page', boardColumnId: 200 }), taskType: 'story' },
        ],
      },
    });

    await userEvent.click(screen.getByRole('button', { name: 'Presets' }));
    await userEvent.click(await screen.findByRole('menuitem', { name: 'All Bugs' }));

    expect(screen.getByText('Fix login crash')).toBeInTheDocument();
    expect(screen.queryByText('Build settings page')).not.toBeInTheDocument();
  });

  // --- per-column add + board settings ---

  it('opens the create-task modal from a column "+" button', async () => {
    renderAuthedPage(<BoardPage />, { props: populatedProps });

    // The add buttons are unnamed ActionIcons (IconPlus); the first column header has one.
    const addButtons = screen.getAllByRole('button');
    const plus = addButtons.find((b) => b.querySelector('svg.tabler-icon-plus'));
    expect(plus).toBeTruthy();
    await userEvent.click(plus!);

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('New Task')).toBeInTheDocument();
  });

  it('opens the Board Settings dialog with editable column rows', async () => {
    renderAuthedPage(<BoardPage />, { props: populatedProps });

    const settingsButton = screen
      .getAllByRole('button')
      .find((b) => b.querySelector('svg.tabler-icon-settings'));
    await userEvent.click(settingsButton!);

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Board Settings')).toBeInTheDocument();
    expect(within(dialog).getByRole('button', { name: 'Add Column' })).toBeInTheDocument();
    // Existing columns are pre-populated as editable name inputs.
    expect(within(dialog).getByDisplayValue('Backlog')).toBeInTheDocument();
    expect(within(dialog).getByDisplayValue('In Progress')).toBeInTheDocument();
  });

  // --- task detail sidebar (driven by the selectedTask prop) ---

  it('renders the task detail sidebar with type/priority badges and the created date', () => {
    renderAuthedPage(<BoardPage />, {
      props: {
        ...populatedProps,
        selectedTask: {
          ...makeTask({ id: 1, title: 'Wire up authentication', boardColumnId: 100 }),
          taskType: 'bug',
          priority: 'high',
        },
        taskComments: [],
        taskAssets: [],
        taskActivities: [],
        taskWorkflowRuns: [],
      },
    });

    // The title also renders on the board card, so scope to the drawer dialog.
    const drawer = within(screen.getByRole('dialog'));
    // The drawer header shows the title plus type and priority badges.
    expect(drawer.getByText('Wire up authentication')).toBeInTheDocument();
    expect(drawer.getByText('bug')).toBeInTheDocument();
    expect(drawer.getByText('high')).toBeInTheDocument();
    // Details tab is selected by default and shows the section labels.
    expect(drawer.getByText('Description')).toBeInTheDocument();
    expect(drawer.getByText('Created')).toBeInTheDocument();
  });

  it('lists workflow runs with status badges and an external link in the detail sidebar', () => {
    renderAuthedPage(<BoardPage />, {
      props: {
        ...populatedProps,
        selectedTask: makeTask({ id: 1, title: 'Wire up authentication', boardColumnId: 100 }),
        taskComments: [],
        taskAssets: [],
        taskActivities: [],
        taskWorkflowRuns: [
          {
            id: 55,
            workflowName: 'Implement Feature',
            state: 'completed',
            mode: 'auto',
            startedAt: null,
            completedAt: null,
            createdAt: '2026-01-02T00:00:00Z',
          },
        ],
      },
    });

    expect(screen.getByText('Workflow Runs (1)')).toBeInTheDocument();
    expect(screen.getByText('completed')).toBeInTheDocument();
    const link = screen.getByRole('link', { name: /Implement Feature/ });
    expect(link).toHaveAttribute('href', '/company/projects/7/workflow_runs/55');
  });

  it('shows the comments empty state and disables Send until text is entered', async () => {
    renderAuthedPage(<BoardPage />, {
      props: {
        ...populatedProps,
        selectedTask: makeTask({ id: 1, title: 'Wire up authentication', boardColumnId: 100 }),
        taskComments: [],
        taskAssets: [],
        taskActivities: [],
        taskWorkflowRuns: [],
      },
    });

    await userEvent.click(screen.getByRole('tab', { name: /Comments/ }));

    expect(screen.getByText('No comments yet.')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Send' })).toBeDisabled();
  });

  it('renders rendered comments with author type badges in the Comments tab', async () => {
    renderAuthedPage(<BoardPage />, {
      props: {
        ...populatedProps,
        selectedTask: { ...makeTask({ id: 1, title: 'Wire up authentication', boardColumnId: 100 }), commentsCount: 1 },
        taskComments: [
          {
            id: 9,
            body: 'Looks good to me',
            authorName: 'Dana Scout',
            authorType: 'human',
            // Use a tag that is NOT one of the composer's quick-tag suggestions so it is unambiguous.
            tags: ['release-blocker'],
            createdAt: '2026-01-02T00:00:00Z',
          },
        ],
        taskAssets: [],
        taskActivities: [],
        taskWorkflowRuns: [],
      },
    });

    await userEvent.click(screen.getByRole('tab', { name: /Comments/ }));

    // The comment body, the author-type badge and the comment tag all render in the Comments panel.
    const drawer = within(screen.getByRole('dialog'));
    expect(drawer.getByText('Looks good to me')).toBeInTheDocument();
    expect(drawer.getByText('human')).toBeInTheDocument();
    expect(drawer.getByText('release-blocker')).toBeInTheDocument();
  });

  it('formats cost, tokens and run time in the Statistics tab', async () => {
    renderAuthedPage(<BoardPage />, {
      props: {
        ...populatedProps,
        selectedTask: makeTask({ id: 1, title: 'Wire up authentication', boardColumnId: 100 }),
        taskComments: [],
        taskAssets: [],
        taskActivities: [],
        taskWorkflowRuns: [],
        taskStatistics: {
          costTotals: { totalCostCents: 250 },
          tokenTotals: { totalTokens: 12500 },
          timeTotals: { totalDurationSeconds: 95 },
          waitStats: [],
          workflowBreakdowns: [],
        },
      },
    });

    // The Statistics tab is the last tab; its label is an icon with no accessible text.
    const tabs = screen.getAllByRole('tab');
    await userEvent.click(tabs[tabs.length - 1]);

    expect(screen.getByText('Total Cost')).toBeInTheDocument();
    expect(screen.getByText('$2.50')).toBeInTheDocument();
    expect(screen.getByText('12.5K')).toBeInTheDocument();
    expect(screen.getByText('1m 35s')).toBeInTheDocument();
  });

  it('offers a Run workflow button when the task column has a workflow binding and no active run', () => {
    renderAuthedPage(<BoardPage />, {
      props: {
        ...populatedProps,
        columns: [
          {
            id: 100,
            name: 'Backlog',
            position: 0,
            purpose: null,
            workflowBinding: { id: 1, workflowId: 5, workflowName: 'Implement', triggerMode: 'manual' },
          },
          { id: 200, name: 'In Progress', position: 1, purpose: null, workflowBinding: null },
        ],
        selectedTask: makeTask({ id: 1, title: 'Wire up authentication', boardColumnId: 100 }),
        taskComments: [],
        taskAssets: [],
        taskActivities: [],
        taskWorkflowRuns: [],
      },
    });

    expect(screen.getByRole('button', { name: 'Run workflow' })).toBeInTheDocument();
  });

  it('opens the delete-confirm modal in the sidebar and closes it on Cancel', async () => {
    renderAuthedPage(<BoardPage />, {
      props: {
        ...populatedProps,
        selectedTask: makeTask({ id: 1, title: 'Wire up authentication', boardColumnId: 100 }),
        taskComments: [],
        taskAssets: [],
        taskActivities: [],
        taskWorkflowRuns: [],
      },
    });

    // The trash ActionIcon in the drawer header opens the confirm modal.
    const trashButton = screen
      .getAllByRole('button')
      .find((b) => b.querySelector('svg.tabler-icon-trash'));
    await userEvent.click(trashButton!);

    expect(await screen.findByText('Delete Task')).toBeInTheDocument();
    expect(screen.getByText(/This action cannot be undone/)).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Cancel' }));
    await waitFor(() => expect(screen.queryByText(/This action cannot be undone/)).not.toBeInTheDocument());
  });

  it('confirms deletion which deletes the task and closes the detail view', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(null, { status: 200 }));

    renderAuthedPage(<BoardPage />, {
      props: {
        ...populatedProps,
        selectedTask: makeTask({ id: 1, title: 'Wire up authentication', boardColumnId: 100 }),
        taskComments: [],
        taskAssets: [],
        taskActivities: [],
        taskWorkflowRuns: [],
      },
    });

    const trashButton = screen
      .getAllByRole('button')
      .find((b) => b.querySelector('svg.tabler-icon-trash'));
    await userEvent.click(trashButton!);

    await userEvent.click(await screen.findByRole('button', { name: 'Delete' }));

    await waitFor(() => expect(fetchSpy).toHaveBeenCalled());
    // handleDeleteTask issues the DELETE then closeTask() navigates back to the bare board URL.
    await waitFor(() => expect(router.get).toHaveBeenCalledWith('/company/projects/7/board', {}, expect.anything()));

    fetchSpy.mockRestore();
  });

  // --- collapse-all toggle ---

  it('collapses every column when the collapse-all toggle is pressed', async () => {
    renderAuthedPage(<BoardPage />, { props: populatedProps });

    // Full columns show their task count chip and full names.
    expect(screen.getByText('Wire up authentication')).toBeInTheDocument();

    const collapseToggle = screen
      .getAllByRole('button')
      .find((b) => b.querySelector('svg.tabler-icon-arrows-minimize'));
    await userEvent.click(collapseToggle!);

    // Collapsed columns no longer render their task cards.
    await waitFor(() => expect(screen.queryByText('Wire up authentication')).not.toBeInTheDocument());
  });
});
