import registry from '../../../../config/agent_runtimes.json';

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

// Badge color is the one thing the registry leaves to the UI. Keyed by AgentType, so a
// runtime added there does not compile until it has one.
const MANTINE_COLORS: Record<AgentType, string> = {
  claude_code: 'orange',
  cursor_cli: 'violet',
  codex: 'teal',
  gemini_cli: 'blue',
  antigravity_cli: 'indigo',
  grok: 'gray',
  kiro_cli: 'grape',
};

/**
 * Every agent runtime the platform launches, in the order pickers list them — the
 * order and copy of config/agent_runtimes.json, which CI builds the images from.
 */
export const AGENT_RUNTIMES = Object.fromEntries(
  registry.runtimes.map((runtime) => [
    runtime.id,
    {
      label: runtime.label,
      productName: runtime.product_name,
      vendor: runtime.vendor,
      description: runtime.description,
      mantineColor: MANTINE_COLORS[runtime.id as AgentType],
    },
  ]),
) as Record<AgentType, AgentRuntime>;

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
