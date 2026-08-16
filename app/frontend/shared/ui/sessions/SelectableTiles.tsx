import { Tooltip } from '@mantine/core';
import { IconCheck } from '@tabler/icons-react';
import type { ReactNode } from 'react';

import { AgentLogo, AGENT_LABELS } from './AgentLogo';
import classes from './SelectableTiles.module.css';

interface FormSectionProps {
  icon: ReactNode;
  children: ReactNode;
  first?: boolean;
}

/** The uppercase, icon-led divider that opens each block of a create drawer. */
export function FormSection({ icon, children, first = false }: FormSectionProps) {
  return (
    <div className={first ? `${classes.section} ${classes.sectionFirst}` : classes.section}>
      <span className={classes.sectionIcon}>{icon}</span>
      {children}
    </div>
  );
}

const RUNTIME_ORDER = ['claude_code', 'cursor_cli', 'codex', 'gemini_cli', 'grok'];

interface RuntimeTilesProps {
  value: string | null;
  onChange: (agentType: string) => void;
  /** Runtimes this user has credentials for. Others render as "Setup". */
  configured: readonly string[];
  /** Where an unconfigured runtime sends the user. */
  setupHint?: string;
}

/** The 2×2 agent-runtime picker shared by both create drawers. */
export function RuntimeTiles({
  value,
  onChange,
  configured,
  setupHint = 'Not configured — connect this runtime in your profile first',
}: RuntimeTilesProps) {
  return (
    <div className={classes.runtimeGrid}>
      {RUNTIME_ORDER.map((agentType) => {
        const isConfigured = configured.includes(agentType);
        const isSelected = value === agentType;

        return (
          <Tooltip key={agentType} label={setupHint} disabled={isConfigured} multiline maw={240}>
            <button
              type="button"
              aria-pressed={isSelected}
              disabled={!isConfigured}
              className={[
                classes.runtime,
                isSelected ? classes.runtimeSelected : '',
                isConfigured ? '' : classes.disabled,
              ]
                .filter(Boolean)
                .join(' ')}
              onClick={() => isConfigured && onChange(agentType)}
            >
              <AgentLogo agentType={agentType} size={18} />
              <span className={classes.runtimeName}>{AGENT_LABELS[agentType]}</span>
              {!isConfigured && <span className={classes.setup}>Setup</span>}
              {isSelected && (
                <span className={classes.tick}>
                  <IconCheck size={14} />
                </span>
              )}
            </button>
          </Tooltip>
        );
      })}
    </div>
  );
}

export interface ModeOption<T extends string> {
  value: T;
  title: string;
  description: string;
}

interface ModeCardsProps<T extends string> {
  options: ModeOption<T>[];
  value: T;
  onChange: (value: T) => void;
  'aria-label': string;
}

/** The execution-mode tag-cards — identical in New Session and Run Workflow. */
export function ModeCards<T extends string>({ options, value, onChange, ...rest }: ModeCardsProps<T>) {
  return (
    <div
      className={classes.modeGrid}
      style={{ gridTemplateColumns: `repeat(${Math.min(options.length, 3)}, 1fr)` }}
      role="radiogroup"
      aria-label={rest['aria-label']}
    >
      {options.map((option) => (
        <button
          key={option.value}
          type="button"
          role="radio"
          aria-checked={option.value === value}
          className={option.value === value ? `${classes.mode} ${classes.modeSelected}` : classes.mode}
          onClick={() => onChange(option.value)}
        >
          <div className={classes.modeTitle}>{option.title}</div>
          <div className={classes.modeDesc}>{option.description}</div>
          {option.value === value && (
            <span className={classes.modeTick}>
              <IconCheck size={14} />
            </span>
          )}
        </button>
      ))}
    </div>
  );
}
