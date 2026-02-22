export interface SubStep {
  id: number;
  stepId: number;
  position: number;
  name: string;
  description: string | null;
  instructions: string | null;
  required: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface Step {
  id: number;
  workflowId: number;
  agentId: number | null;
  position: number;
  name: string;
  description: string | null;
  instructions: string | null;
  allowNonInteractive: boolean;
  skipPolicy: 'never' | 'if_outputs_exist' | 'manual';
  onFailure: 'retry' | 'skip' | 'fail';
  maxRetries: number;
  inputAssetSpecs: AssetSpec[];
  outputAssetSpecs: AssetSpec[];
  toolIds: number[];
  mcpServerIds: number[];
  skillIds: number[];
  mountRepositories: boolean;
  subSteps: SubStep[];
  createdAt: string;
  updatedAt: string;
}

export interface AssetSpec {
  name: string;
  assetType: string;
  required: boolean;
  namePattern?: string;
}

export interface CreateStepRequest {
  name: string;
  position: number;
  description?: string;
  instructions?: string;
  agentId?: number | null;
  allowNonInteractive?: boolean;
  skipPolicy?: string;
  onFailure?: string;
  maxRetries?: number;
  subStepsAttributes?: SubStepAttribute[];
}

export interface UpdateStepRequest {
  id: number;
  name?: string;
  description?: string;
  instructions?: string;
  agentId?: number | null;
  allowNonInteractive?: boolean;
  skipPolicy?: string;
  onFailure?: string;
  maxRetries?: number;
  inputAssetSpecs?: AssetSpec[];
  outputAssetSpecs?: AssetSpec[];
  toolIds?: number[];
  mcpServerIds?: number[];
  skillIds?: number[];
  mountRepositories?: boolean;
  subStepsAttributes?: SubStepAttribute[];
}

export interface SubStepAttribute {
  id?: number;
  name: string;
  position: number;
  description?: string;
  instructions?: string;
  required?: boolean;
  _destroy?: boolean;
}
