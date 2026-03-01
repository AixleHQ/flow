export interface BoardTask {
  id: number;
  title: string;
  description: string | null;
  taskType: string;
  priority: string | null;
  assigneeId: number | null;
  assigneeName: string | null;
  boardColumnId: number;
  position: number;
  parentTaskId: number | null;
  tags: string[];
  childrenCount: number;
  commentsCount: number;
  assetsCount: number;
  activeWorkflowRun: { id: number; status: string } | null;
  createdAt: string;
  updatedAt: string;
}

export interface WorkflowBinding {
  workflowId: number;
  workflowName: string;
  triggerMode: 'auto' | 'manual';
  cooldownSeconds: number;
}

export interface BoardColumn {
  id: number;
  name: string;
  position: number;
  purpose: string | null;
  workflowBinding: WorkflowBinding | null;
  createdAt: string;
  updatedAt: string;
}

export interface Board {
  id: number;
  name: string;
  presetOrigin: string | null;
  createdAt: string;
  updatedAt: string;
  boardColumns: BoardColumn[];
}

export interface TaskComment {
  id: number;
  body: string;
  authorId: number;
  authorName: string;
  authorType: string;
  tags: string[];
  createdAt: string;
}

export interface TaskAsset {
  id: number;
  name: string;
  fileUrl: string | null;
  fileSize: number | null;
  contentType: string | null;
  tags: string[];
  authorId: number;
  authorType: string;
  createdAt: string;
  updatedAt: string;
}

export interface BoardActivity {
  id: number;
  eventType: string;
  actorId: number;
  actorType: string;
  actorName: string;
  boardTaskId: number | null;
  taskTitle: string | null;
  description: string;
  metadata: Record<string, unknown>;
  createdAt: string;
}

export interface TaskWorkflowRun {
  id: number;
  workflowName: string;
  state: string;
  mode: string;
  startedAt: string | null;
  completedAt: string | null;
  createdAt: string;
}

export interface PaginatedResponse<T> {
  meta: { page: number; perPage: number; totalPages: number; totalCount: number };
  items: T[];
}

export const TASK_TYPE_COLORS: Record<string, string> = {
  epic: '#9c27b0',
  story: '#1976d2',
  bug: '#d32f2f',
  not_specified: '#9e9e9e',
};

export const PRIORITY_COLORS: Record<string, string> = {
  critical: '#d32f2f',
  high: '#ed6c02',
  medium: '#eab308',
  low: '#2e7d32',
};

export const COMMENT_TAG_SUGGESTIONS = [
  'feedback',
  'tech_design',
  'code_review',
  'qa_report',
  'implementation_notes',
] as const;
