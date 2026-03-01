export type ProjectTab =
  | 'overview'
  | 'board'
  | 'assets'
  | 'repositories'
  | 'workflows'
  | 'runs'
  | 'sessions'
  | 'config'
  | 'agents'
  | 'tools'
  | 'mcp-servers'
  | 'skills'
  | 'members'
  | 'settings'
  | 'analytics';

export interface IWorkflowParameter {
  name: string;
  type: 'string' | 'number' | 'boolean';
  description?: string;
  defaultValue?: string | number | boolean;
  required: boolean;
}

export interface IWorkflow {
  id: number;
  name: string;
  description?: string;
  stepsCount: number;
  scopeIndicator?: 'company' | 'project';
  lastRunAt?: string;
  lastRunStatus?: 'completed' | 'running' | 'error';
  parameters?: IWorkflowParameter[];
}

export interface IWorkflowRun {
  id: string;
  workflowId: string;
  workflowName: string;
  status: 'running' | 'completed' | 'error';
  startedAt: string;
  completedAt?: string;
  userId: string;
  userName: string;
  totalCost?: number;
  currentStep?: number;
  totalSteps: number;
}

export interface ITask {
  id: string;
  title: string;
  status: 'backlog' | 'todo' | 'in_progress' | 'done';
  priority?: 'low' | 'medium' | 'high' | 'urgent';
  assigneeId?: string;
  assigneeName?: string;
  linearId?: string;
  linearUrl?: string;
}
