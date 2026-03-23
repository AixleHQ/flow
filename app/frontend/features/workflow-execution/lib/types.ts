export interface SubStepRunInfo {
  id: number;
  subStepId: number;
  state: 'pending' | 'in_progress' | 'completed' | 'skipped';
  note: string | null;
  data: Record<string, unknown> | null;
  subStepName: string;
  startedAt: string | null;
  completedAt: string | null;
}

export interface StepFailureRecord {
  errorMessage: string | null;
  failedAt: string | null;
}

export interface StepRunInfo {
  id: number;
  workflowRunId: number;
  stepId: number;
  terminalSessionId: number | null;
  state: 'pending' | 'running' | 'waiting_input' | 'completed' | 'failed' | 'skipped';
  stepNote: string | null;
  skipReason: string | null;
  errorMessage: string | null;
  stepName: string;
  stepPosition: number;
  subStepRuns: SubStepRunInfo[];
  startedAt: string | null;
  completedAt: string | null;
  createdAt: string;
  pastFailures: StepFailureRecord[];
}

export interface CurrentStepInfo {
  id: number;
  stepId: number;
  stepName: string;
  stepPosition: number;
  state: string;
}

export interface WorkflowRun {
  id: number;
  workflowId: number;
  projectId: number;
  userId: number;
  state: 'pending' | 'running' | 'paused' | 'completed' | 'failed' | 'cancelled';
  mode: 'interactive' | 'non_interactive' | 'mixed';
  stepOverrides: Record<string, StepOverride>;
  inputAssetIds: number[];
  repositoryIds: number[];
  agentRuntime: string | null;
  sharedContext: Record<string, unknown>;
  workflowName: string;
  currentStepInfo: CurrentStepInfo | null;
  stepRuns: StepRunInfo[];
  startedAt: string | null;
  completedAt: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface StepOverride {
  autoRun: boolean;
}

export interface CreateWorkflowRunRequest {
  workflowId: number;
  mode: 'interactive' | 'non_interactive' | 'mixed';
  stepOverrides?: Record<string, StepOverride>;
  inputAssetIds?: number[];
  repositoryIds?: number[];
  agentRuntime?: string;
}

export interface WorkflowRunAsset {
  id: number;
  workflowRunId: number;
  producedByStepRunId: number | null;
  name: string;
  s3Key: string | null;
  contentType: string | null;
  fileSize: number | null;
  downloadUrl: string | null;
  createdAt: string;
}
