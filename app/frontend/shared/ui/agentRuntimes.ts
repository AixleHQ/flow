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

/** The words AgentCredential::PreflightError::NO_CREDENTIALS refuses the launch with server-side. */
export const NO_AGENT_CREDENTIALS = 'No agent credentials. Connect an agent in Profile settings to run workflows.';

export const AGENT_SELECT_OPTIONS = AGENT_TYPES.map((type) => ({ value: type, label: AGENT_RUNTIMES[type].label }));

export function isAgentType(value: string | null | undefined): value is AgentType {
  return !!value && Object.hasOwn(AGENT_RUNTIMES, value);
}

/** `claude_code` → `Claude Code`; unknown runtimes fall back to the raw id. */
export function agentLabel(agentType: string | null | undefined): string {
  if (!agentType) return '—';
  return isAgentType(agentType) ? AGENT_RUNTIMES[agentType].label : agentType;
}

interface ReasoningEffortSpec {
  levels: string[];
  requires_model: boolean;
  models: { match: string; levels: string[] }[];
}

const REASONING_EFFORT: Record<string, ReasoningEffortSpec | undefined> = Object.fromEntries(
  registry.runtimes.map((runtime) => [runtime.id, runtime.reasoning_effort as ReasoningEffortSpec | undefined]),
);

const REASONING_EFFORT_LABELS: Record<string, string> = {
  low: 'Low',
  medium: 'Medium',
  high: 'High',
  xhigh: 'Extra high',
  max: 'Max',
  ultra: 'Ultra',
};

export function reasoningEffortLabel(level: string): string {
  return REASONING_EFFORT_LABELS[level] ?? level;
}

/**
 * The reasoning-effort levels a runtime's CLI takes for `model` (null: its default
 * model), in config/agent_runtimes.json's order — the same rule as
 * AgentRuntime#reasoning_effort_levels on the server.
 */
export function reasoningEffortLevels(runtime: string | null | undefined, model?: string | null): string[] {
  const spec = runtime ? REASONING_EFFORT[runtime] : undefined;
  if (!spec) return [];
  if (spec.requires_model && !model) return [];

  const rule = model ? spec.models.find((entry) => new RegExp(entry.match).test(model)) : undefined;
  return rule ? rule.levels : spec.levels;
}

/** Why a runtime offers no reasoning-effort level for `model`, or null when it offers some. */
export function reasoningEffortUnavailableReason(
  runtime: string | null | undefined,
  model?: string | null,
): string | null {
  if (!runtime) return 'Choose a runtime to set a reasoning effort.';
  if (reasoningEffortLevels(runtime, model).length > 0) return null;

  const label = agentLabel(runtime);
  const spec = REASONING_EFFORT[runtime];
  if (spec?.requires_model && !model) return `${label} sets a reasoning effort only on a model you choose.`;
  if (spec && model) return `${label} has no reasoning-effort setting for ${model}.`;
  return `${label} has no reasoning-effort setting.`;
}
