import { Select, type SelectProps } from '@mantine/core';

import {
  agentLabel,
  reasoningEffortLabel,
  reasoningEffortLevels,
  reasoningEffortUnavailableReason,
} from 'shared/ui/agentRuntimes';

interface ReasoningEffortSelectProps extends Omit<SelectProps, 'data' | 'value' | 'onChange' | 'error'> {
  /** The runtime whose levels are offered; null offers none. */
  runtime: string | null | undefined;
  /** The model the session launches on — null for the runtime's default model. */
  model: string | null | undefined;
  value: string | null;
  onChange: (value: string | null) => void;
}

function unsupportedLevel(
  value: string,
  runtime: string | null | undefined,
  model: string | null | undefined,
  levels: string[],
): string {
  const target = model ? `${agentLabel(runtime)} with ${model}` : agentLabel(runtime);
  return `${reasoningEffortLabel(value)} is not available for ${target}. Choose one of: ${levels.map(reasoningEffortLabel).join(', ')}.`;
}

/**
 * Picks a reasoning-effort level from the ones the runtime (and, where it matters, the
 * model) takes, per config/agent_runtimes.json. Empty is the CLI's own default. With
 * no level to offer it is disabled and says why; a saved level the runtime or model no
 * longer takes stays visible as an error, so it is cleared on purpose, not lost.
 */
export function ReasoningEffortSelect({
  runtime,
  model,
  value,
  onChange,
  disabled,
  placeholder = "Default (the CLI's own)",
  ...props
}: ReasoningEffortSelectProps) {
  const levels = reasoningEffortLevels(runtime, model);
  const reason = reasoningEffortUnavailableReason(runtime, model);
  const unsupported = !!value && !levels.includes(value);

  const data = levels.map((level) => ({ value: level, label: reasoningEffortLabel(level) }));
  if (value && unsupported) data.push({ value, label: reasoningEffortLabel(value) });

  const error = unsupported ? (reason ?? unsupportedLevel(value, runtime, model, levels)) : undefined;

  return (
    <Select
      {...props}
      data={data}
      value={value}
      onChange={(next) => onChange(next || null)}
      placeholder={placeholder}
      clearable
      allowDeselect
      disabled={disabled || (levels.length === 0 && !value)}
      description={!unsupported && reason ? reason : props.description}
      error={error}
    />
  );
}
