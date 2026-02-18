export interface IProject {
  id: number;
  name: string;
  description?: string | null;
  slug: string;
  state: 'active' | 'paused' | 'archived';
  company_id: number;
  owner_id: number;
  collaborators_count: number;
  last_activity_at?: string | null;
  created_at: string;
  updated_at: string;
}

export interface IProjectStats {
  totalTasks: number;
  activeTasks: number;
  totalWorkflowRuns: number;
  totalCost: number;
}
