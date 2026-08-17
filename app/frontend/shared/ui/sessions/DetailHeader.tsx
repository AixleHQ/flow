import { Link } from '@inertiajs/react';
import type { ReactNode } from 'react';

import { AgentLogo, agentLabel } from './AgentLogo';
import classes from './DetailHeader.module.css';
import { ModeTag, modeLabel } from './ModeTag';
import { StatusTag } from './StatusTag';

export interface Crumb {
  label: string;
  href?: string;
}

export interface HeaderStat {
  label: string;
  value: ReactNode;
  /** Prose values (dates, model chips) drop the mono face. */
  sans?: boolean;
  color?: string;
}

export interface TokenBreakdown {
  inputTokens: number;
  outputTokens: number;
  cacheReadTokens: number;
  cacheWriteTokens: number;
}

interface DetailHeaderProps {
  crumbs: Crumb[];
  title: string;
  state?: string | null;
  statusLabel?: string;
  /** `#1986` or `Run #1443` — printed after the status chip. */
  identifier?: string;
  description?: string | null;
  agentType?: string | null;
  userName?: string | null;
  mode?: string | null;
  /** Extra meta pairs appended after runtime · by user · mode. */
  extraMeta?: { label: string; value: ReactNode }[];
  stats?: HeaderStat[];
  tokens?: TokenBreakdown | null;
  /** Right-hand side of the breadcrumb row: labels and one action at most. */
  actions?: ReactNode;
  /** Tabs render flush against the header's bottom edge. */
  tabs?: ReactNode;
  formatTokenValue: (n: number) => string;
}

/**
 * The shared run/session detail header. Every caller passes the same shape, so
 * a run and the session inside it read as the same object at two depths.
 */
export function DetailHeader({
  crumbs,
  title,
  state,
  statusLabel,
  identifier,
  description,
  agentType,
  userName,
  mode,
  extraMeta = [],
  stats = [],
  tokens,
  actions,
  tabs,
  formatTokenValue,
}: DetailHeaderProps) {
  const hasMeta = !!agentType || !!userName || !!mode || extraMeta.length > 0;

  return (
    <header className={classes.head} style={tabs ? { paddingBottom: 0, borderBottom: 0 } : undefined}>
      <div className={classes.backRow}>
        <nav className={classes.crumbs} aria-label="Breadcrumb">
          {crumbs.map((crumb, i) => (
            <span key={`${crumb.label}-${i}`} style={{ display: 'inline-flex', alignItems: 'center', gap: 7 }}>
              {i > 0 && (
                <span className={classes.crumbSep} aria-hidden="true">
                  ›
                </span>
              )}
              {crumb.href ? (
                <Link href={crumb.href} className={classes.crumb}>
                  {crumb.label}
                </Link>
              ) : (
                <span className={classes.crumbCurrent} aria-current="page">
                  {crumb.label}
                </span>
              )}
            </span>
          ))}
        </nav>
        <div className={classes.spacer} />
        {actions && <div className={classes.actions}>{actions}</div>}
      </div>

      <div className={classes.titleRow}>
        <h1 className={classes.title}>{title}</h1>
        {state && <StatusTag state={state}>{statusLabel}</StatusTag>}
        {identifier && <span className={classes.idx}>{identifier}</span>}
        <ModeTag mode={mode} />
      </div>

      {description && <p className={classes.desc}>{description}</p>}

      {hasMeta && (
        <div className={classes.meta}>
          {agentType && (
            <span className={classes.metaItem}>
              <AgentLogo agentType={agentType} size={15} />
              <b className={classes.metaValue}>{agentLabel(agentType)}</b>
            </span>
          )}
          {userName && (
            <span className={classes.metaItem}>
              <span className={classes.metaKey}>by</span> {userName}
            </span>
          )}
          {mode && (
            <span className={classes.metaItem}>
              <span className={classes.metaKey}>Mode</span> {modeLabel(mode)}
            </span>
          )}
          {extraMeta.map((item) => (
            <span className={classes.metaItem} key={item.label}>
              <span className={classes.metaKey}>{item.label}</span> {item.value}
            </span>
          ))}
        </div>
      )}

      {stats.length > 0 && (
        <div className={classes.stats}>
          {stats.map((stat) => (
            <div className={classes.stat} key={stat.label}>
              <div className={classes.statKey}>{stat.label}</div>
              <div
                className={stat.sans ? `${classes.statValue} ${classes.statValueSans}` : classes.statValue}
                style={stat.color ? { color: stat.color } : undefined}
              >
                {stat.value}
              </div>
            </div>
          ))}
        </div>
      )}

      {tokens && (
        <div className={classes.tokenLine}>
          <span className={classes.tokenLineKey}>Tokens</span>
          <span>
            Input <b>{formatTokenValue(tokens.inputTokens)}</b>
          </span>
          <span className={classes.tokenLineSep}>·</span>
          <span>
            Output <b>{formatTokenValue(tokens.outputTokens)}</b>
          </span>
          <span className={classes.tokenLineSep}>·</span>
          <span>
            Cache read <b>{formatTokenValue(tokens.cacheReadTokens)}</b>
          </span>
          <span className={classes.tokenLineSep}>·</span>
          <span>
            Cache write <b>{formatTokenValue(tokens.cacheWriteTokens)}</b>
          </span>
        </div>
      )}

      {tabs}
    </header>
  );
}
