import type BoardColumn from 'types/generated/BoardColumn';
import type BoardTask from 'types/generated/BoardTask';
import type TaskDetail from 'types/generated/TaskDetail';

export type Column = BoardColumn;

export type Gate = BoardTask['pendingGates'][number];

// The board list payload plus the two fields only the drawer's detail payload carries: with one page
// per column loaded, the board cannot find an archived parent epic or an epic's children itself.
export type Task = BoardTask & Partial<Pick<TaskDetail, 'parentTaskTitle' | 'childTasks'>>;

export interface BoardFilters {
  assigneeId: string | null;
  taskType: string | null;
  priority: string | null;
  tags: string[];
  search: string;
  showArchived: boolean;
}

export interface ColState {
  id: number | null;
  name: string;
  purpose: string;
  workflowId: string | null;
  triggerMode: string;
  bindingId: number | null;
  bindingChanged: boolean;
}

// Categorical, so these read from the chart ramp rather than Material hexes;
// priority is a severity scale, so it reads from the status tokens.
export const TASK_TYPE_COLORS: Record<string, string> = {
  epic: 'var(--app-chart-5)',
  story: 'var(--app-chart-2)',
  bug: 'var(--app-danger-fg)',
  not_specified: 'var(--app-text-tertiary)',
};

export const PRIORITY_COLORS: Record<string, string> = {
  critical: 'var(--app-danger-fg)',
  high: 'var(--app-warning-fg)',
  medium: 'var(--app-chart-4)',
  low: 'var(--app-success-fg)',
};

export const jsonHeaders = { 'Content-Type': 'application/json' };
