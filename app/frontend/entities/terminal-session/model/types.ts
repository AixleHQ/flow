// Terminal Session Types
export type TerminalSessionState =
  | 'not_started'
  | 'running'
  | 'ready'
  | 'finished'
  | 'failed';

export type TerminalSessionType = 'auth_setup' | 'agent_session' | 'tool_setup' | 'workflow_step';

export type AgentType = 'claude_code' | 'cursor_cli' | 'codex' | 'gemini_cli';

export type SessionMode = 'interactive' | 'non_interactive';

export interface ISessionConfig {
  configFiles?: Record<string, string>;
  envVars?: Record<string, string>;
}

export interface ITerminalSession {
  id: number;
  sessionType: TerminalSessionType;
  agentType: AgentType;
  state: TerminalSessionState;
  projectId: number | null;
  containerId: string | null;
  routeToken: string | null;
  websocketUrl: string | null;
  watcherUrl: string | null;
  ideUrl: string | null;
  artifactsPath: string | null;
  errorMessage: string | null;
  metadata: Record<string, unknown>;
  sessionConfig: ISessionConfig | null;
  // Normalized config (from join tables + columns)
  toolIds: number[];
  skillIds: number[];
  mcpServerIds: number[];
  inputAssetIds: number[];
  repositoryIds: number[];
  configuredAgentId: number | null;
  mode: SessionMode;
  initialPrompt: string | null;
  startedAt: string | null;
  readyAt: string | null;
  finishedAt: string | null;
  createdAt: string;
  updatedAt: string;
  // Usage (denormalized)
  totalTokens: number;
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
  costCents: number;
  models: string[];
  // Artifact review
  artifactsReviewed: boolean;
  pendingArtifactsCount: number;
  sessionLogsCount: number;
  // Relations
  userName: string | null;
  userEmail: string | null;
  projectName: string | null;
}

export interface ICreateTerminalSessionRequest {
  terminalSession: {
    sessionType: TerminalSessionType;
    agentType: AgentType;
    projectId?: number;
    toolIds?: number[];
    skillIds?: number[];
    mcpServerIds?: number[];
    inputAssetIds?: number[];
    repositoryIds?: number[];
    configuredAgentId?: number;
    mode?: SessionMode;
    initialPrompt?: string;
    metadata?: Record<string, unknown>;
    sessionConfig?: ISessionConfig;
  };
}

export interface ICreateTerminalSessionResponse {
  data: ITerminalSession;
}

export interface IGetTerminalSessionResponse {
  data: ITerminalSession;
}

export interface IPaginationMeta {
  page: number;
  perPage: number;
  totalPages: number;
  totalCount: number;
}

export interface IListTerminalSessionsResponse {
  items: ITerminalSession[];
  meta: IPaginationMeta;
}

export interface IListTerminalSessionsParams {
  projectId?: number;
  sessionType?: TerminalSessionType;
  agentType?: AgentType;
  state?: TerminalSessionState;
  createdAfter?: string;
  createdBefore?: string;
  page?: number;
  perPage?: number;
}

export interface IFinishAuthResponse {
  data: ITerminalSession;
  message: string;
}

export interface ICancelSessionResponse {
  data: ITerminalSession;
  message: string;
}

export interface ISessionArtifact {
  id: number;
  name: string;
  folder: string | null;
  status: string;
  fileSize: number | null;
  contentType: string | null;
  downloadUrl: string | null;
  createdAt: string;
}

export interface IReviewArtifactsRequest {
  sessionId: number;
  decisions: Record<string, 'save' | 'dismiss'>;
}
