export interface IProject {
  id: number;
  name: string;
  description?: string | null;
  slug: string;
  state: 'active' | 'paused' | 'archived';
  companyId: number;
  ownerId: number;
  collaboratorsCount: number;
  lastActivityAt?: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface IProjectStats {
  totalTasks: number;
  activeTasks: number;
  totalWorkflowRuns: number;
  totalCost: number;
}
