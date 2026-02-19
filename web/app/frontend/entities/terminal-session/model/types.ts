// Terminal Session Types
export type TerminalSessionState =
  | 'not_started'
  | 'started'
  | 'running'
  | 'stopped'
  | 'collected'
  | 'failed'
  | 'cancelled';

export type TerminalSessionType = 'auth_setup' | 'agent_session' | 'tool_setup' | 'workflow_step';

export type AgentType = 'claude_code' | 'cursor_cli' | 'codex' | 'gemini_cli';

export type SessionMode = 'interactive' | 'non_interactive';

export interface ISessionConfig {
  agentId?: number;
  toolIds?: number[];
  skillIds?: number[];
  mcpServerIds?: number[];
  mode?: SessionMode;
  initialPrompt?: string;
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
  artifactsPath: string | null;
  errorMessage: string | null;
  metadata: Record<string, unknown>;
  sessionConfig: ISessionConfig | null;
  startedAt: string | null;
  finishedAt: string | null;
  collectedAt: string | null;
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
