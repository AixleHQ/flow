import { Select, type SelectProps } from '@mantine/core';

import { agentLabel, reasoningEffortLabel } from 'shared/ui/agentRuntimes';

interface ReasoningEffortSelectProps extends Omit<SelectProps, 'data' | 'value' | 'onChange' | 'error'> {
  /** The runtime the session runs on, for the messages; null offers none. */
  runtime: string | null | undefined;
  /** The explicitly chosen model the session launches on; null offers none. */
  model: string | null | undefined;
  /**
   * The levels the server says this runtime takes for `model`
   * (the selected model option's `reasoningEffortLevels`). Undefined when the
   * server listed no such model, so its levels are not known here.
   */
  levels: string[] | undefined;
  value: string | null;
  onChange: (value: string | null) => void;
}

/** The registry lists a runtime's levels; whether a given model honours each one is up to its CLI. */
const REASONING_EFFORT_HINT = "The CLI may lower or ignore a level the model doesn't support.";

/** Why no level is offered, or null when some are. */
function unavailableReason(
  runtime: string | null | undefined,
  model: string | null | undefined,
  levels: string[] | undefined,
): string | null {
  if (!runtime) return 'Choose a runtime to set a reasoning effort.';
  if (!model) return 'Choose a model to set a reasoning effort.';
  if (!levels) return `${agentLabel(runtime)} doesn't list ${model}, so its reasoning-effort levels are unknown.`;
  if (levels.length > 0) return null;
  return `${agentLabel(runtime)} has no reasoning-effort setting for ${model}.`;
}

function unsupportedLevel(value: string, runtime: string | null | undefined, model: string, levels: string[]): string {
  return `${reasoningEffortLabel(value)} is not available for ${agentLabel(runtime)} with ${model}. Choose one of: ${levels.map(reasoningEffortLabel).join(', ')}.`;
}

/**
 * Picks a reasoning-effort level from the ones the server computed for the selected
 * model. Empty is the CLI's own default. With no level to offer it is disabled and
 * says why; a saved level the model doesn't take stays visible as an error, so it is
 * cleared on purpose, not lost. With levels to offer it says that the CLI may still
 * lower or ignore one the model lacks.
 */
export function ReasoningEffortSelect({
  runtime,
  model,
  levels,
  value,
  onChange,
  disabled,
  placeholder = "Default (the CLI's own)",
  ...props
}: ReasoningEffortSelectProps) {
  const offered = levels ?? [];
  const reason = unavailableReason(runtime, model, levels);
  // A level is flagged only when the server's list for the model is known.
  let error: string | undefined;
  if (value && model && levels && !levels.includes(value)) {
    error = levels.length > 0 ? unsupportedLevel(value, runtime, model, levels) : (reason ?? undefined);
  }
  const unsupported = error !== undefined;

  const data = offered.map((level) => ({ value: level, label: reasoningEffortLabel(level) }));
  if (value && !offered.includes(value)) data.push({ value, label: reasoningEffortLabel(value) });

  const hint = offered.length > 0 ? REASONING_EFFORT_HINT : undefined;
  const description = !unsupported && reason ? reason : (props.description ?? hint);

  return (
    <Select
      {...props}
      data={data}
      value={value}
      onChange={(next) => onChange(next || null)}
      placeholder={placeholder}
      clearable
      allowDeselect
      disabled={disabled || (offered.length === 0 && !value)}
      description={description}
      error={error}
    />
  );
}
