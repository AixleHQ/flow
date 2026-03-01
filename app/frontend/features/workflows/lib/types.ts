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
  baseToolIds: number[];
  baseSkillIds: number[];
  baseMcpServerIds: number[];
  baseAssetIds: number[];
  inheritAllProjectResources: boolean;
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
  config?: Record<string, unknown>;
}
