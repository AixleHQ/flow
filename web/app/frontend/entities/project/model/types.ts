export interface IProject {
  id: string;
  name: string;
  description?: string;
  companyId: string;
  artifactsCount: number;
  tasksCount: number;
  activeTasksCount: number;
  workflowsCount: number;
  lastActivityAt?: string;
  createdAt: string;
  updatedAt: string;
}

export interface IProjectStats {
  totalArtifacts: number;
  totalTasks: number;
  activeTasks: number;
  totalWorkflowRuns: number;
  totalCost: number;
}
