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
  startedAt: string | null;
  finishedAt: string | null;
  collectedAt: string | null;
  createdAt: string;
  updatedAt: string;
}

export interface ICreateTerminalSessionRequest {
  terminalSession: {
    sessionType: TerminalSessionType;
    agentType: AgentType;
    projectId?: number;
    metadata?: Record<string, unknown>;
  };
}

export interface ICreateTerminalSessionResponse {
  data: ITerminalSession;
}

export interface IGetTerminalSessionResponse {
  data: ITerminalSession;
}

export interface IListTerminalSessionsResponse {
  items: ITerminalSession[];
}

export interface IFinishAuthResponse {
  data: ITerminalSession;
  message: string;
}

export interface ICancelSessionResponse {
  data: ITerminalSession;
  message: string;
}
