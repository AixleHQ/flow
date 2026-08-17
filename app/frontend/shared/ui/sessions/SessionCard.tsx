import { Link } from '@inertiajs/react';
import { IconCheck, IconChevronRight, IconX } from '@tabler/icons-react';
import { useState } from 'react';

import { formatCost, formatDuration, formatTokens } from 'shared/lib/sessionFormat';

import { AgentLogo, agentLabel } from './AgentLogo';
import classes from './SessionCard.module.css';
import { StatusTag } from './StatusTag';

export interface SessionCardStep {
  id: number;
  label: string;
  state: string;
}

export interface SessionCardData {
  /** Step-run id — the card's identity inside the run. */
  id: number;
  /** "Session 1" / "Step 1" — the ordinal label. */
  ordinal: string;
  title: string;
  state: string;
  terminalSessionId: number | null;
  agentType: string | null;
  totalTokens: number;
  costCents: number;
  startedAt: string | null;
  completedAt: string | null;
  excerpt: string | null;
  prompt: string | null;
  note: string | null;
  errorMessage: string | null;
  steps: SessionCardStep[];
}

const STEP_STATE_LABELS: Record<string, string> = {
  completed: 'Done',
  failed: 'Failed',
  in_progress: 'Running',
  running: 'Running',
  skipped: 'Skipped',
  pending: 'Pending',
};

function StepIcon({ state }: { state: string }) {
  if (state === 'completed') return <IconCheck size={13} color="var(--app-success-fg)" />;
  if (state === 'failed') return <IconX size={13} color="var(--app-danger-fg)" />;
  if (state === 'in_progress' || state === 'running') return <span className={classes.spinner} />;
  return <span className={classes.pendingRing} />;
}

function stepStateColor(state: string): string {
  if (state === 'completed') return 'var(--app-success-fg)';
  if (state === 'failed') return 'var(--app-danger-fg)';
  if (state === 'in_progress' || state === 'running') return 'var(--app-warning-fg)';
  return 'var(--app-text-tertiary)';
}

interface SessionCardProps {
  data: SessionCardData;
  /** Where "Open session →" goes. Omitted when the session has not started. */
  sessionHref?: string | null;
  /** Start expanded — the live session in a running run does. */
  defaultOpen?: boolean;
  /** Accent the border, for the session currently producing output. */
  live?: boolean;
}

/** One session inside a workflow run, collapsed to an excerpt until opened. */
export function SessionCard({ data, sessionHref, defaultOpen = false, live = false }: SessionCardProps) {
  const [open, setOpen] = useState(defaultOpen);
  const doneCount = data.steps.filter((s) => s.state === 'completed').length;
  const duration = formatDuration(data.startedAt, data.completedAt, data.state);

  return (
    <article className={live ? `${classes.card} ${classes.live}` : classes.card}>
      <div className={classes.top}>
        <button
          type="button"
          className={open ? `${classes.caret} ${classes.caretOpen}` : classes.caret}
          aria-expanded={open}
          aria-label={open ? `Collapse ${data.title}` : `Expand ${data.title}`}
          onClick={() => setOpen((v) => !v)}
        >
          <IconChevronRight size={14} />
        </button>
        <span className={classes.stepNo}>{data.ordinal}</span>
        <span className={classes.title}>{data.title}</span>
        <StatusTag state={data.state} />
        {sessionHref && (
          <Link href={sessionHref} className={classes.go}>
            Open session <IconChevronRight size={13} />
          </Link>
        )}
      </div>

      <div className={classes.meta}>
        {data.agentType && (
          <span className={classes.agent}>
            <AgentLogo agentType={data.agentType} size={16} />
            {agentLabel(data.agentType)}
          </span>
        )}
        {data.terminalSessionId && <span className={`${classes.num} ${classes.dim}`}>#{data.terminalSessionId}</span>}
        {data.totalTokens > 0 && <span className={classes.num}>{formatTokens(data.totalTokens)} tokens</span>}
        {data.costCents > 0 && <span className={classes.num}>{formatCost(data.costCents)}</span>}
        <span className={`${classes.num} ${classes.dim}`}>{duration}</span>
      </div>

      {!open && data.excerpt && <p className={classes.excerpt}>{data.excerpt}</p>}

      {open && (
        <div className={classes.expand}>
          {data.prompt && (
            <section className={classes.section}>
              <h4 className={classes.sectionHead}>Prompt</h4>
              <p className={classes.prompt}>{data.prompt}</p>
            </section>
          )}

          {data.steps.length > 0 && (
            <section className={classes.section}>
              <h4 className={classes.sectionHead}>
                Steps
                <span className={classes.sectionCount}>
                  {doneCount}/{data.steps.length}
                </span>
              </h4>
              {data.steps.map((step) => (
                <div className={classes.sub} key={step.id}>
                  <span className={classes.subIcon}>
                    <StepIcon state={step.state} />
                  </span>
                  <span className={classes.subLabel}>{step.label}</span>
                  <span className={classes.subState} style={{ color: stepStateColor(step.state) }}>
                    {STEP_STATE_LABELS[step.state] ?? step.state}
                  </span>
                </div>
              ))}
            </section>
          )}

          {data.note && (
            <section className={classes.section}>
              <h4 className={classes.sectionHead}>Result note</h4>
              <p className={classes.note}>{data.note}</p>
            </section>
          )}

          {data.errorMessage && (
            <section className={classes.section}>
              <h4 className={classes.sectionHead}>Error</h4>
              <div className={classes.errorBox}>{data.errorMessage}</div>
            </section>
          )}
        </div>
      )}
    </article>
  );
}
