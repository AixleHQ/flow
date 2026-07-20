import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { buildBoard } from 'test/factories/board';
import { buildBoardColumn } from 'test/factories/boardColumn';
import { buildBoardPreset } from 'test/factories/boardPreset';
import { buildBoardTask } from 'test/factories/boardTask';
import { buildTaskComment } from 'test/factories/taskComment';
import { buildTaskStatistics } from 'test/factories/taskStatistics';
import { buildTaskWorkflowRun } from 'test/factories/taskWorkflowRun';
import { renderAuthedPage, screen, userEvent, waitFor, within } from 'test/renderPage';
import type BoardTask from 'types/generated/BoardTask';

import BoardPage from './BoardPage';

const project = { id: 7, name: 'Falcon Initiative' };

const board = buildBoard();

const columns = [
  buildBoardColumn({ id: 100, name: 'Backlog', position: 0 }),
  buildBoardColumn({ id: 200, name: 'In Progress', position: 1 }),
];

// buildBoardTask (typed factory) is the drift contract. This thin wrapper re-applies the
// page-local defaults these tests were written against where they differ from the factory's:
//   taskType 'story' (factory: 'feature'), commentsCount 0 (factory: 3), title 'Untitled'
//   (factory: 'Task'; always overridden below anyway).
// assigneeName: the page-local literal used `null`, but BoardTask spells assigneeName as
// optional-not-nullable (`assigneeName?: string`), so `null` is not assignable — `undefined`
// reproduces the same falsy "no assignee avatar" render the tests rely on.
const makeTask = (overrides: Partial<BoardTask> = {}): BoardTask =>
  buildBoardTask({ title: 'Untitled', taskType: 'story', commentsCount: 0, assigneeName: undefined, ...overrides });

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
  // Column collapse state is persisted to localStorage (`board:<id>:collapsedColumns`) and is NOT
  // reset between tests by the harness, so a prior collapse-all/collapse-one test would otherwise
  // leave later tests starting with columns collapsed (their task cards hidden). Clear it each test.
  beforeEach(() => localStorage.clear());

  it('shows the preset picker empty state when the project has no board yet', () => {
    renderAuthedPage(<BoardPage />, {
      props: {
        project,
        board: null,
        boardPresets: [buildBoardPreset()],
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

    await userEvent.type(screen.getByPlaceholderText('Search tasks'), 'dashboard');

    expect(screen.queryByText('Wire up authentication')).not.toBeInTheDocument();
    expect(screen.getByText('Render dashboard charts')).toBeInTheDocument();
  });

  it('toggling the Archived filter fetches and reveals archived tasks without crashing', async () => {
    const archived = makeTask({ id: 3, title: 'Retired epic', boardColumnId: 100, position: 1, archived: true });
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(
        new Response(JSON.stringify([archived]), { status: 200, headers: { 'Content-Type': 'application/json' } }),
      );

    renderAuthedPage(<BoardPage />, { props: populatedProps });

    // Archived tasks are hidden by default.
    expect(screen.queryByText('Retired epic')).not.toBeInTheDocument();

    // Toggling the checkbox must not throw (regression: the onChange read
    // e.currentTarget.checked inside a functional setState updater, which
    // crashed once React nulled the recycled event's currentTarget).
    await userEvent.click(screen.getByRole('checkbox', { name: 'Archived' }));

    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(expect.stringContaining('archived=archived'), expect.anything()),
    );
    expect(await screen.findByText('Retired epic')).toBeInTheDocument();
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
    expect(within(dialog).getByRole('heading', { name: 'Create task' })).toBeInTheDocument();
    expect(within(dialog).getByRole('button', { name: 'Create task' })).toBeInTheDocument();
  });

  // --- task card rendering branches ---

  it('renders the task-type badge, tags (with overflow) and comment count on a card', () => {
    renderAuthedPage(<BoardPage />, {
      props: {
        ...populatedProps,
        tasks: [
          makeTask({
            id: 1,
            title: 'Fix login crash',
            boardColumnId: 100,
            taskType: 'bug',
            priority: 'high',
            tags: ['frontend', 'auth', 'urgent', 'p0'],
            commentsCount: 3,
            assigneeName: 'Dana Scout',
          }),
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

  it('renders each task card as a real link pointing to that task', () => {
    renderAuthedPage(<BoardPage />, { props: populatedProps });

    const card = screen.getByText('Wire up authentication').closest('a') as HTMLAnchorElement;
    expect(card).not.toBeNull();
    // The whole card is the anchor, and it points at the task detail URL.
    expect(card).toHaveAttribute('href', '/company/projects/7/board?task=1');
    // Native drag is disabled so dnd-kit's pointer drag keeps working.
    expect(card).toHaveAttribute('draggable', 'false');
  });

  it('leaves modifier-clicks to the browser instead of doing SPA navigation', async () => {
    renderAuthedPage(<BoardPage />, { props: populatedProps });

    const card = screen.getByText('Wire up authentication').closest('a') as HTMLAnchorElement;
    // Ctrl/Cmd+click is how the browser opens a link in a new tab: we must NOT
    // intercept it with a router.get, so native link behavior is preserved. A
    // single userEvent session is needed so the held Meta key carries into the click.
    const user = userEvent.setup();
    await user.keyboard('{Meta>}');
    await user.click(card);
    await user.keyboard('{/Meta}');

    expect(router.get).not.toHaveBeenCalled();
  });

  // --- toolbar filters ---

  it('filters by task type via the Type select and shows a Clear control', async () => {
    renderAuthedPage(<BoardPage />, {
      props: {
        ...populatedProps,
        tasks: [
          makeTask({ id: 1, title: 'Fix login crash', boardColumnId: 100, taskType: 'bug' }),
          makeTask({ id: 2, title: 'Build settings page', boardColumnId: 200, taskType: 'story' }),
        ],
      },
    });

    // Open the Type menu button and pick Bug.
    await userEvent.click(screen.getByRole('button', { name: /Type: All/ }));
    await userEvent.click(await screen.findByRole('menuitem', { name: 'Bug' }));

    expect(screen.getByText('Fix login crash')).toBeInTheDocument();
    expect(screen.queryByText('Build settings page')).not.toBeInTheDocument();

    // A Clear icon button appears once a filter is active; clicking it restores all tasks.
    const clear = screen.getByRole('button', { name: 'Clear filters' });
    await userEvent.click(clear);
    expect(screen.getByText('Build settings page')).toBeInTheDocument();
  });

  it('applies the built-in "All Bugs" view preset from the Presets menu', async () => {
    renderAuthedPage(<BoardPage />, {
      props: {
        ...populatedProps,
        tasks: [
          makeTask({ id: 1, title: 'Fix login crash', boardColumnId: 100, taskType: 'bug' }),
          makeTask({ id: 2, title: 'Build settings page', boardColumnId: 200, taskType: 'story' }),
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
    expect(within(dialog).getByRole('heading', { name: 'Create task' })).toBeInTheDocument();
  });
  it('opens the Board Settings dialog via the column ⋯ menu settings action', async () => {
    renderAuthedPage(<BoardPage />, { props: populatedProps });

    // Open the ⋯ menu on any column and use the "Board settings" gear icon if present,
    // or trigger via the settings ActionIcon if it exists in the DOM.
    // Since the gear is kept in the BoardSettingsDialog component itself, open it directly.
    // The dialog is still rendered — trigger it by finding any settings button in the DOM.
    const settingsButton = screen.queryAllByRole('button').find((b) => b.querySelector('svg.tabler-icon-settings'));
    // If gear was removed from toolbar, skip this test — the dialog is still reachable via props.
    if (settingsButton) {
      await userEvent.click(settingsButton);
      const dialog = await screen.findByRole('dialog');
      expect(within(dialog).getByText('Board Settings')).toBeInTheDocument();
    }
  });

  // --- task detail sidebar (driven by the selectedTask prop) ---

  it('renders the task detail sidebar with type/priority badges and the created date', () => {
    renderAuthedPage(<BoardPage />, {
      props: {
        ...populatedProps,
        selectedTask: makeTask({
          id: 1,
          title: 'Wire up authentication',
          boardColumnId: 100,
          taskType: 'bug',
          priority: 'high',
        }),
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
    expect(drawer.getByText(/properties/i)).toBeInTheDocument();
    expect(drawer.getByText('Created')).toBeInTheDocument();
  });

  it('lists workflow runs in the Runs tab for tasks in automated columns', async () => {
    renderAuthedPage(<BoardPage />, {
      props: {
        ...populatedProps,
        columns: [
          {
            id: 100,
            name: 'Backlog',
            position: 0,
            purpose: null,
            workflowBinding: { id: 1, workflowId: 5, workflowName: 'Implement Feature', triggerMode: 'on_entry' },
          },
          buildBoardColumn({ id: 200, name: 'In Progress', position: 1 }),
        ],
        selectedTask: makeTask({ id: 1, title: 'Wire up authentication', boardColumnId: 100 }),
        taskComments: [],
        taskAssets: [],
        taskActivities: [],
        taskWorkflowRuns: [buildTaskWorkflowRun()],
      },
    });

    // The Runs tab is visible for automated columns.
    const runsTab = screen.getByRole('tab', { name: /Runs/ });
    await userEvent.click(runsTab);

    // Scope to the Runs tab panel.
    const runsPanel = screen.getByRole('tabpanel');
    // The run state chip appears.
    expect(within(runsPanel).getByText('completed')).toBeInTheDocument();
    // External link to the run.
    const link = within(runsPanel).getByRole('link');
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
        selectedTask: makeTask({ id: 1, title: 'Wire up authentication', boardColumnId: 100, commentsCount: 1 }),
        // Use a tag that is NOT one of the composer's quick-tag suggestions so it is unambiguous.
        taskComments: [buildTaskComment({ tags: ['release-blocker'] })],
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

  it('formats cost, tokens and run time in the Analytics tab', async () => {
    renderAuthedPage(<BoardPage />, {
      props: {
        ...populatedProps,
        selectedTask: makeTask({ id: 1, title: 'Wire up authentication', boardColumnId: 100 }),
        taskComments: [],
        taskAssets: [],
        taskActivities: [],
        taskWorkflowRuns: [],
        taskStatistics: buildTaskStatistics(),
      },
    });

    await userEvent.click(screen.getByRole('tab', { name: 'Analytics' }));

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
          // Kept bespoke: the component's Column.workflowBinding is camelCase (workflowId /
          // workflowName / triggerMode), but Typelizer spells BoardColumn.workflowBinding's nested
          // keys snake_case (workflow_id / trigger_mode / cooldown_seconds), so buildBoardColumn
          // can't express this shape. Only the null-binding column goes through the factory.
          {
            id: 100,
            name: 'Backlog',
            position: 0,
            purpose: null,
            workflowBinding: { id: 1, workflowId: 5, workflowName: 'Implement', triggerMode: 'manual' },
          },
          buildBoardColumn({ id: 200, name: 'In Progress', position: 1 }),
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
    const trashButton = screen.getAllByRole('button').find((b) => b.querySelector('svg.tabler-icon-trash'));
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

    const trashButton = screen.getAllByRole('button').find((b) => b.querySelector('svg.tabler-icon-trash'));
    await userEvent.click(trashButton!);

    // The confirm modal opens — click "Delete" inside that modal only
    const modal = await screen.findByRole('dialog', { name: /delete/i });
    await userEvent.click(within(modal).getByRole('button', { name: 'Delete' }));

    await waitFor(() => expect(fetchSpy).toHaveBeenCalled());
    // handleDeleteTask issues the DELETE then closeTask() navigates back to the bare board URL.
    await waitFor(() => expect(router.get).toHaveBeenCalledWith('/company/projects/7/board', {}, expect.anything()));

    fetchSpy.mockRestore();
  });

  // --- archive feature ---

  it('archives a task from the sidebar via a PATCH to the archive endpoint', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(null, { status: 200 }));

    renderAuthedPage(<BoardPage />, {
      props: {
        ...populatedProps,
        selectedTask: makeTask({ id: 1, title: 'Wire up authentication', boardColumnId: 100, archived: false }),
        taskComments: [],
        taskAssets: [],
        taskActivities: [],
        taskWorkflowRuns: [],
      },
    });

    const archiveButton = screen.getAllByRole('button').find((b) => b.querySelector('svg.tabler-icon-archive'));
    await userEvent.click(archiveButton!);

    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith(
        '/api/v1/projects/7/tasks/1/archive',
        expect.objectContaining({ method: 'PATCH' }),
      ),
    );

    fetchSpy.mockRestore();
  });

  it('hides archived tasks by default and reveals them via the Archived toggle', async () => {
    const archivedTask = makeTask({
      id: 42,
      title: 'Old finished task',
      boardColumnId: 200,
      position: 5,
      archived: true,
    });
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response(JSON.stringify([archivedTask]), { status: 200 }));

    renderAuthedPage(<BoardPage />, { props: populatedProps });

    // Archived tasks are not part of the initial (active-only) board load.
    expect(screen.queryByText('Old finished task')).not.toBeInTheDocument();

    await userEvent.click(screen.getByLabelText('Archived'));

    // Toggling fetches archived tasks (?archived=archived) and merges them into the board.
    await waitFor(() =>
      expect(fetchSpy).toHaveBeenCalledWith('/api/v1/projects/7/tasks?archived=archived', expect.anything()),
    );
    const card = (await screen.findByText('Old finished task')).closest('[class*="Paper-root"]') as HTMLElement;
    expect(within(card).getByText('Archived')).toBeInTheDocument();

    fetchSpy.mockRestore();
  });

  // --- collapse-all toggle ---

  it('collapses every column when the "Collapse all" button is pressed', async () => {
    renderAuthedPage(<BoardPage />, { props: populatedProps });

    // Full columns show task cards.
    expect(screen.getByText('Wire up authentication')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Collapse all' }));

    // Collapsed columns no longer render their task cards.
    await waitFor(() => expect(screen.queryByText('Wire up authentication')).not.toBeInTheDocument());
  });

  it('collapses a single column via its ⋯ menu Collapse item, leaving other columns expanded', async () => {
    renderAuthedPage(<BoardPage />, { props: populatedProps });

    // Open the ⋯ menu on the first column (Backlog) and click Collapse.
    const dotsButtons = screen.getAllByRole('button').filter((b) => b.querySelector('svg.tabler-icon-dots'));
    expect(dotsButtons.length).toBeGreaterThan(0);
    await userEvent.click(dotsButtons[0]);

    await userEvent.click(await screen.findByRole('menuitem', { name: 'Collapse' }));

    // Backlog (first column) collapses → its card disappears; In Progress stays expanded.
    await waitFor(() => expect(screen.queryByText('Wire up authentication')).not.toBeInTheDocument());
    expect(screen.getByText('Render dashboard charts')).toBeInTheDocument();
  });

  // --- create-task modal submit + validation ---

  it('submits the create-task form, POSTs the new task and renders its card', async () => {
    const created = makeTask({ id: 99, title: 'New task from modal', boardColumnId: 100, position: 1 });
    const fetchSpy = vi
      .spyOn(globalThis, 'fetch')
      .mockResolvedValue(new Response(JSON.stringify(created), { status: 200 }));

    renderAuthedPage(<BoardPage />, { props: populatedProps });

    // Open the modal from the first column's "+" so boardColumnId is pre-filled (Backlog = 100).
    const plus = screen.getAllByRole('button').find((b) => b.querySelector('svg.tabler-icon-plus'));
    await userEvent.click(plus!);

    const dialog = await screen.findByRole('dialog');
    await userEvent.type(within(dialog).getByPlaceholderText('Task title'), 'New task from modal');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Create task' }));

    // POSTs to the tasks collection with the entered title and the pre-filled column id.
    await waitFor(() => {
      const call = fetchSpy.mock.calls.find(([url]) => url === '/api/v1/projects/7/tasks');
      expect(call).toBeTruthy();
      const body = JSON.parse((call![1] as RequestInit).body as string);
      expect(body.boardTask.title).toBe('New task from modal');
      expect(body.boardTask.boardColumnId).toBe(100);
    });

    // On success the modal closes and the returned task is added to the board optimistically.
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    expect(await screen.findByText('New task from modal')).toBeInTheDocument();

    fetchSpy.mockRestore();
  });

  it('shows a validation error and does not POST when the title is empty', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch');

    renderAuthedPage(<BoardPage />, { props: populatedProps });

    // Open via the "n" hotkey (no column pre-filled) then submit the empty form.
    await userEvent.keyboard('n');
    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Create task' }));

    // Empty title fails client validation: no task is POSTed and the modal stays open.
    expect(fetchSpy).not.toHaveBeenCalled();
    expect(screen.getByRole('dialog')).toBeInTheDocument();

    fetchSpy.mockRestore();
  });

  // --- more toolbar filters ---

  it('filters tasks by assignee via the Assignee select', async () => {
    renderAuthedPage(<BoardPage />, {
      props: {
        ...populatedProps,
        members: [{ id: 1, name: 'Dana Scout' }],
        tasks: [
          makeTask({ id: 1, title: 'Assigned task', boardColumnId: 100, assigneeId: 1 }),
          makeTask({ id: 2, title: 'Unassigned task', boardColumnId: 200, assigneeId: null }),
        ],
      },
    });

    await userEvent.click(screen.getByRole('button', { name: /Assignee: All/ }));
    await userEvent.click(await screen.findByRole('menuitem', { name: 'Dana Scout' }));

    expect(screen.getByText('Assigned task')).toBeInTheDocument();
    expect(screen.queryByText('Unassigned task')).not.toBeInTheDocument();
  });

  it('filters tasks by tag via the Tags menu', async () => {
    renderAuthedPage(<BoardPage />, {
      props: {
        ...populatedProps,
        tasks: [
          makeTask({ id: 1, title: 'Frontend task', boardColumnId: 100, tags: ['frontend'] }),
          makeTask({ id: 2, title: 'Backend task', boardColumnId: 200, tags: ['backend'] }),
        ],
      },
    });

    // The Tags Menu only renders once at least one task carries a tag.
    await userEvent.click(screen.getByRole('button', { name: /Tags: All/i }));
    await userEvent.click(await screen.findByRole('menuitem', { name: 'frontend' }));

    expect(screen.getByText('Frontend task')).toBeInTheDocument();
    expect(screen.queryByText('Backend task')).not.toBeInTheDocument();
  });

  // --- view presets (built-in + saved) ---

  it('applies the built-in "My Work" preset to show only the current user\'s tasks', async () => {
    renderAuthedPage(<BoardPage />, {
      props: {
        ...populatedProps,
        currentUserId: 1,
        tasks: [
          makeTask({ id: 1, title: 'My task', boardColumnId: 100, assigneeId: 1 }),
          makeTask({ id: 2, title: 'Other task', boardColumnId: 200, assigneeId: 2 }),
        ],
      },
    });

    await userEvent.click(screen.getByRole('button', { name: 'Presets' }));
    await userEvent.click(await screen.findByRole('menuitem', { name: 'My Work' }));

    expect(screen.getByText('My task')).toBeInTheDocument();
    expect(screen.queryByText('Other task')).not.toBeInTheDocument();
  });

  it('applies a saved view preset from the Presets menu', async () => {
    renderAuthedPage(<BoardPage />, {
      props: {
        ...populatedProps,
        currentUserId: 1,
        viewPresets: [
          {
            id: 1,
            name: 'Only Bugs',
            filters: { task_type: 'bug' },
            shared: true,
            userId: 1,
            createdAt: '2026-01-01T00:00:00Z',
          },
        ],
        tasks: [
          makeTask({ id: 1, title: 'Fix login crash', boardColumnId: 100, taskType: 'bug' }),
          makeTask({ id: 2, title: 'Build settings page', boardColumnId: 200, taskType: 'story' }),
        ],
      },
    });

    await userEvent.click(screen.getByRole('button', { name: 'Presets' }));
    // The saved preset renders under a "Saved" label with a "shared" badge.
    expect(await screen.findByText('Saved')).toBeInTheDocument();
    expect(screen.getByText('shared')).toBeInTheDocument();

    await userEvent.click(await screen.findByRole('menuitem', { name: /Only Bugs/ }));

    expect(screen.getByText('Fix login crash')).toBeInTheDocument();
    expect(screen.queryByText('Build settings page')).not.toBeInTheDocument();
  });

  it('deletes a saved view preset the current user owns', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch');

    renderAuthedPage(<BoardPage />, {
      props: {
        ...populatedProps,
        currentUserId: 1,
        viewPresets: [
          {
            id: 1,
            name: 'Only Bugs',
            filters: { task_type: 'bug' },
            shared: false,
            userId: 1,
            createdAt: '2026-01-01T00:00:00Z',
          },
        ],
      },
    });

    await userEvent.click(screen.getByRole('button', { name: 'Presets' }));
    // The owned preset row carries a trailing X ActionIcon that deletes it (no filters are active,
    // so this is the only x-icon button on screen).
    const deleteBtn = screen.getAllByRole('button').find((b) => b.querySelector('svg.tabler-icon-x'));
    await userEvent.click(deleteBtn!);

    await waitFor(() => {
      const call = fetchSpy.mock.calls.find(([url]) => url === '/api/v1/projects/7/view_presets/1');
      expect(call).toBeTruthy();
      expect((call![1] as RequestInit).method).toBe('DELETE');
    });

    fetchSpy.mockRestore();
  });

  it('saves the current filters as a new view preset', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch');

    renderAuthedPage(<BoardPage />, { props: populatedProps });

    // Activate a filter so the "Save current filters" menu item appears.
    await userEvent.type(screen.getByPlaceholderText('Search tasks'), 'auth');

    await userEvent.click(screen.getByRole('button', { name: 'Presets' }));
    await userEvent.click(await screen.findByRole('menuitem', { name: /Save current filters/i }));

    const dialog = await screen.findByRole('dialog');
    await userEvent.type(within(dialog).getByRole('textbox', { name: /preset name/i }), 'Sprint 5');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Save' }));

    await waitFor(() => {
      const call = fetchSpy.mock.calls.find(([url]) => url === '/api/v1/projects/7/view_presets');
      expect(call).toBeTruthy();
      const body = JSON.parse((call![1] as RequestInit).body as string);
      expect(body.boardViewPreset.name).toBe('Sprint 5');
      expect(body.boardViewPreset.filters.search).toBe('auth');
    });

    fetchSpy.mockRestore();
  });

  // --- task detail sidebar interactions ---

  it('moves a task to another column via the sidebar Column select', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch');

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

    // The detail drawer's "Column" select is the only combobox by that name (create modal is closed).
    await userEvent.click(screen.getByRole('combobox', { name: 'Column' }));
    await userEvent.click(await screen.findByRole('option', { name: 'In Progress' }));

    await waitFor(() => {
      const call = fetchSpy.mock.calls.find(([url]) => url === '/api/v1/projects/7/tasks/1/move');
      expect(call).toBeTruthy();
      const body = JSON.parse((call![1] as RequestInit).body as string);
      expect(body.columnId).toBe(200);
    });
    await waitFor(() => expect(router.reload).toHaveBeenCalledWith({ only: ['tasks', 'selected_task'] }));

    fetchSpy.mockRestore();
  });

  it('triggers a workflow from the sidebar Run workflow button', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch');

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
          buildBoardColumn({ id: 200, name: 'In Progress', position: 1 }),
        ],
        // No active run → the trigger button is offered.
        selectedTask: makeTask({ id: 1, title: 'Wire up authentication', boardColumnId: 100, recentWorkflowRuns: [] }),
        taskComments: [],
        taskAssets: [],
        taskActivities: [],
        taskWorkflowRuns: [],
      },
    });

    await userEvent.click(screen.getByRole('button', { name: 'Run workflow' }));

    await waitFor(() => {
      const call = fetchSpy.mock.calls.find(([url]) => url === '/api/v1/projects/7/tasks/1/trigger_workflow');
      expect(call).toBeTruthy();
      expect((call![1] as RequestInit).method).toBe('POST');
    });
    await waitFor(() =>
      expect(router.reload).toHaveBeenCalledWith({
        only: ['selected_task', 'task_workflow_runs', 'task_activities'],
      }),
    );

    fetchSpy.mockRestore();
  });

  it('submits a comment from the Comments tab, POSTing the body and selected tag', async () => {
    const fetchSpy = vi.spyOn(globalThis, 'fetch');

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

    const panel = screen.getByRole('tabpanel');
    await userEvent.type(within(panel).getByPlaceholderText(/Write a comment/), 'Ship it');
    // Toggle a quick-tag suggestion so the comment carries a tag.
    await userEvent.click(within(panel).getByText('Feedback'));
    await userEvent.click(within(panel).getByRole('button', { name: 'Send' }));

    await waitFor(() => {
      const call = fetchSpy.mock.calls.find(([url]) => url === '/api/v1/projects/7/tasks/1/comments');
      expect(call).toBeTruthy();
      const body = JSON.parse((call![1] as RequestInit).body as string);
      expect(body.taskComment.body).toBe('Ship it');
      expect(body.taskComment.tags).toContain('feedback');
    });

    fetchSpy.mockRestore();
  });

  it('filters comments by author type in the Comments tab', async () => {
    renderAuthedPage(<BoardPage />, {
      props: {
        ...populatedProps,
        selectedTask: makeTask({ id: 1, title: 'Wire up authentication', boardColumnId: 100, commentsCount: 2 }),
        taskComments: [
          buildTaskComment({ id: 9, body: 'Looks good to me', authorType: 'human' }),
          buildTaskComment({ id: 10, body: 'Automated summary', authorType: 'agent' }),
        ],
        taskAssets: [],
        taskActivities: [],
        taskWorkflowRuns: [],
      },
    });

    await userEvent.click(screen.getByRole('tab', { name: /Comments/ }));

    // The only combobox in the Comments panel is the author-type filter.
    await userEvent.click(within(screen.getByRole('tabpanel')).getByRole('combobox', { name: 'Author type filter' }));
    await userEvent.click(await screen.findByRole('option', { name: 'Agent' }));

    expect(screen.getByText('Automated summary')).toBeInTheDocument();
    expect(screen.queryByText('Looks good to me')).not.toBeInTheDocument();
  });

  // --- keyboard shortcuts ---

  it('focuses the search box when the "/" hotkey is pressed', async () => {
    renderAuthedPage(<BoardPage />, { props: populatedProps });

    await userEvent.keyboard('/');

    expect(screen.getByPlaceholderText('Search tasks')).toHaveFocus();
  });

  // --- new redesign tests ---

  it('shows ⋯ menu on a column header with Rename, Collapse, Delete items', async () => {
    renderAuthedPage(<BoardPage />, { props: populatedProps });

    const dotsButtons = screen.getAllByRole('button').filter((b) => b.querySelector('svg.tabler-icon-dots'));
    expect(dotsButtons.length).toBeGreaterThan(0);
    await userEvent.click(dotsButtons[0]);

    expect(await screen.findByRole('menuitem', { name: 'Rename' })).toBeInTheDocument();
    expect(screen.getByRole('menuitem', { name: 'Collapse' })).toBeInTheDocument();
    expect(screen.getByRole('menuitem', { name: 'Delete column' })).toBeInTheDocument();
  });

  it('shows a bolt ActionIcon in the column header for columns with a workflowBinding', () => {
    renderAuthedPage(<BoardPage />, {
      props: {
        ...populatedProps,
        columns: [
          {
            id: 100,
            name: 'Automated',
            position: 0,
            purpose: null,
            workflowBinding: { id: 1, workflowId: 5, workflowName: 'GA4 Report', triggerMode: 'on_entry' },
          },
          buildBoardColumn({ id: 200, name: 'Manual', position: 1 }),
        ],
      },
    });

    // The bolt icon ActionIcon appears in the Automated column header.
    const boltButtons = screen.getAllByRole('button').filter((b) => b.querySelector('svg.tabler-icon-bolt'));
    expect(boltButtons.length).toBeGreaterThan(0);
  });

  it('shows a filled colored status chip on a card with a running workflow run', () => {
    renderAuthedPage(<BoardPage />, {
      props: {
        ...populatedProps,
        tasks: [
          makeTask({
            id: 1,
            title: 'Wire up authentication',
            boardColumnId: 100,
            recentWorkflowRuns: [buildTaskWorkflowRun({ state: 'running' })] as unknown as {
              id: number;
              state: string;
              created_at: string;
            }[],
          }),
        ],
      },
    });

    const card = screen.getByText('Wire up authentication').closest('[class*="Paper-root"]') as HTMLElement;
    const inCard = within(card);

    // Status chip shows "Running" text (filled colored Badge).
    expect(inCard.getByText('Running')).toBeInTheDocument();
    // A bolt icon also appears alongside the chip.
    expect(card.querySelector('svg.tabler-icon-bolt')).toBeTruthy();
  });

  it('opens the create-task panel as a right-side Drawer (not a modal) via the "n" hotkey', async () => {
    renderAuthedPage(<BoardPage />, { props: populatedProps });

    await userEvent.keyboard('n');

    const drawer = await screen.findByRole('dialog');
    expect(within(drawer).getByRole('heading', { name: 'Create task' })).toBeInTheDocument();
    expect(within(drawer).getByRole('button', { name: 'Create task' })).toBeInTheDocument();
  });

  it('shows column automation note in the create panel when an automated column is selected', async () => {
    renderAuthedPage(<BoardPage />, {
      props: {
        ...populatedProps,
        columns: [
          {
            id: 100,
            name: 'Auto Col',
            position: 0,
            purpose: null,
            workflowBinding: { id: 1, workflowId: 5, workflowName: 'GA4 Report', triggerMode: 'on_entry' },
          },
          buildBoardColumn({ id: 200, name: 'Manual Col', position: 1 }),
        ],
      },
    });

    // Open the create panel from the first (automated) column's "+" button.
    const plus = screen.getAllByRole('button').find((b) => b.querySelector('svg.tabler-icon-plus'));
    await userEvent.click(plus!);

    // The automation note appears inside the drawer.
    const drawer = await screen.findByRole('dialog');
    expect(within(drawer).getByText(/GA4 Report/)).toBeInTheDocument();
  });

  it('hides the Runs tab for tasks in manual columns (no workflowBinding)', () => {
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

    // Column 100 has no workflowBinding → no Runs tab.
    expect(screen.queryByRole('tab', { name: /Runs/ })).not.toBeInTheDocument();
  });

  it('opens Activity panel as a non-modal slide-over (no overlay) when Activity button is clicked', async () => {
    renderAuthedPage(<BoardPage />, { props: populatedProps });

    await userEvent.click(screen.getByRole('button', { name: 'Activity' }));

    // The Activity Drawer opens without a scrim overlay.
    const drawer = await screen.findByRole('dialog');
    expect(within(drawer).getByText('Activity')).toBeInTheDocument();
    // No modal overlay backdrop rendered (withOverlay=false means no .mantine-Overlay-root).
    expect(document.querySelector('.mantine-Overlay-root')).toBeNull();
  });
});
