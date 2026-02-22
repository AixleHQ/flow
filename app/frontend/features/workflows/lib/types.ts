export interface Workflow {
  id: number;
  name: string;
  description: string | null;
  config: Record<string, unknown>;
  scopeType: string;
  scopeId: number;
  scopeIndicator: 'company' | 'project';
  stepsCount: number;
  lastRunAt: string | null;
  lastRunStatus: string | null;
  hasActiveRuns: boolean;
  descriptionExcerpt: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface CreateWorkflowRequest {
  name: string;
  description?: string;
}

export interface UpdateWorkflowRequest {
  id: number;
  name?: string;
  description?: string;
}
