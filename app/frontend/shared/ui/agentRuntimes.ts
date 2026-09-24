import type { AgentType } from './types';

interface AgentRuntime {
  /** Short name, for pickers, tables and badges. */
  label: string;
  /** The product's own name, where the runtime is introduced (profile, onboarding). */
  productName: string;
  vendor: string;
  /** One line introducing the runtime where a user connects it. */
  description: string;
  /** Mantine palette color for the runtime's badges. */
  mantineColor: string;
}

/**
 * Every agent runtime the platform launches, in the order pickers list them. Keyed by
 * AgentType, so a runtime added there does not compile until it is described here.
 */
export const AGENT_RUNTIMES: Record<AgentType, AgentRuntime> = {
  claude_code: {
    label: 'Claude Code',
    productName: 'Claude Code',
    vendor: 'Anthropic',
    description: "Anthropic's AI coding assistant with deep reasoning capabilities",
    mantineColor: 'orange',
  },
  cursor_cli: {
    label: 'Cursor CLI',
    productName: 'Cursor CLI',
    vendor: 'Cursor',
    description: 'AI-powered code editor with context-aware suggestions',
    mantineColor: 'violet',
  },
  codex: {
    label: 'Codex',
    productName: 'OpenAI Codex',
    vendor: 'OpenAI',
    description: "OpenAI's code generation model optimized for multiple languages",
    mantineColor: 'teal',
  },
  gemini_cli: {
    label: 'Gemini CLI',
    productName: 'Gemini CLI',
    vendor: 'Google',
    description: "Google's multimodal AI for code and documentation tasks",
    mantineColor: 'blue',
  },
  antigravity_cli: {
    label: 'Antigravity CLI',
    productName: 'Antigravity CLI',
    vendor: 'Google',
    description: "Google's agent-first terminal runtime, signed in with your Google account",
    mantineColor: 'indigo',
  },
  grok: {
    label: 'Grok',
    productName: 'Grok',
    vendor: 'xAI',
    description: "xAI's Grok CLI for agentic coding in the terminal",
    mantineColor: 'gray',
  },
  kiro_cli: {
    label: 'Kiro CLI',
    productName: 'Kiro CLI',
    vendor: 'AWS',
    description: "AWS's Kiro CLI for spec-driven agentic coding in the terminal",
    mantineColor: 'grape',
  },
};

export const AGENT_TYPES = Object.keys(AGENT_RUNTIMES) as AgentType[];

export const AGENT_SELECT_OPTIONS = AGENT_TYPES.map((type) => ({ value: type, label: AGENT_RUNTIMES[type].label }));

export function isAgentType(value: string | null | undefined): value is AgentType {
  return !!value && Object.hasOwn(AGENT_RUNTIMES, value);
}

/** `claude_code` → `Claude Code`; unknown runtimes fall back to the raw id. */
export function agentLabel(agentType: string | null | undefined): string {
  if (!agentType) return '—';
  return isAgentType(agentType) ? AGENT_RUNTIMES[agentType].label : agentType;
}
