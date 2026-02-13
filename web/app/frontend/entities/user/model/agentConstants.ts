import type { AgentType } from './types';

export interface IAgentInfo {
  type: AgentType;
  name: string;
  description: string;
}

export const AVAILABLE_AGENTS: IAgentInfo[] = [
  {
    type: 'claude_code',
    name: 'Claude Code',
    description: "Anthropic's AI coding assistant with deep reasoning capabilities",
  },
  {
    type: 'cursor_cli',
    name: 'Cursor CLI',
    description: 'AI-powered code editor with context-aware suggestions',
  },
  {
    type: 'codex',
    name: 'OpenAI Codex',
    description: "OpenAI's code generation model optimized for multiple languages",
  },
  {
    type: 'gemini_cli',
    name: 'Gemini CLI',
    description: "Google's multimodal AI for code and documentation tasks",
  },
];

export const AGENT_COLORS: Record<AgentType, string> = {
  codex: '#10a37f',
  cursor_cli: '#7c3aed',
  gemini_cli: '#3b82f6',
  claude_code: '#d97706',
};

export const getAgentInfo = (type: AgentType): IAgentInfo => AVAILABLE_AGENTS.find((a) => a.type === type)!;
