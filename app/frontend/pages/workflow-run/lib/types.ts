export type StepStatus = 'completed' | 'running' | 'running_other' | 'pending' | 'error';

export interface IWorkflowStep {
  id: string;
  name: string;
  status: StepStatus;
  agent?: string;
  user?: string;
  duration?: string;
  cost?: number;
  startedAt?: string;
  completedAt?: string;
  assets?: Array<{
    id: string;
    name: string;
    type: string;
  }>;
}

export interface IWorkflowRunDetail {
  id: string;
  workflowId: string;
  workflowName: string;
  projectId: string;
  projectName: string;
  status: 'running' | 'completed' | 'error';
  startedAt: string;
  completedAt?: string;
  userId: string;
  userName: string;
  totalCost: number;
  steps: IWorkflowStep[];
}
