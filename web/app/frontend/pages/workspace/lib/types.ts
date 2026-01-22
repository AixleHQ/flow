export type AgentType = 'codex' | 'cursor_cli' | 'gemini_cli' | 'claude_code';

export interface IAgent {
  type: AgentType;
  displayName: string;
  image: string;
  configured: boolean;
}

export interface IAgentSession {
  id: string;
  agentType: AgentType;
  status: 'idle' | 'starting' | 'running' | 'stopping' | 'error';
  ttydPort?: number;
  watcherPort?: number;
  error?: string;
}

// Response types after camelCase conversion by baseApi
export interface ICreateSessionResponse {
  id: string;
  agentType: AgentType;
  status: string;
  ttyd?: {
    port: number;
    wsUrl: string;
  };
  watcher?: {
    port: number;
    wsUrl: string;
    httpUrl: string;
  };
  createdAt: string;
}

export interface IAgentsResponse {
  agents: IAgent[];
}
