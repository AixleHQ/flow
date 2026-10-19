import type { ReactNode } from 'react';

import { deltaOf, type DeltaField, type TenantSummary, type Totals } from './aggregate';
import classes from './Dashboard.module.css';
import { formatCount, formatHours, formatPercent } from './format';
import type { BillingClass, Snapshot } from './types';

interface Props {
  snapshot: Snapshot;
  latestClasses: BillingClass[];
  rows: TenantSummary[];
  totals: Totals | null;
  previous: Totals | null;
}

interface TileProps {
  label: string;
  value: string;
  delta?: { field: DeltaField; current: number; previous: number | null | undefined };
  children?: ReactNode;
}

function Tile({ label, value, delta, children }: TileProps) {
  const change = delta ? deltaOf(delta.field, delta.current, delta.previous ?? null) : null;
  const tone = change && change.tone !== 'neutral' ? classes[change.tone] : '';
  return (
    <section className={classes.tile} aria-label={label}>
      <h2 className={classes.tileLabel}>{label}</h2>
      <p className={classes.tileValue}>{value}</p>
      {change && <p className={`${classes.delta} ${tone}`}>{change.text}</p>}
      {children && <p className={classes.tileNote}>{children}</p>}
    </section>
  );
}

const COMPANY_CLASSES: { billingClass: BillingClass; label: string }[] = [
  { billingClass: 'paying', label: 'paying' },
  { billingClass: 'trial', label: 'trial' },
  { billingClass: 'managed', label: 'managed' },
  { billingClass: 'blocked', label: 'blocked' },
];

const UNBILLED: BillingClass[] = ['unlimited', 'no_customer'];

/** The platform's size as it stands, then what the selected period used. */
export default function Tiles({ snapshot, latestClasses, rows, totals, previous }: Props) {
  const count = (wanted: BillingClass[]) =>
    latestClasses.filter((billingClass) => wanted.includes(billingClass)).length;
  const split = COMPANY_CLASSES.flatMap(({ billingClass, label }) => {
    const n = count([billingClass]);
    return n ? [`${n} ${label}`] : [];
  });
  const unbilled = count(UNBILLED);
  const freeBusy = rows.filter((row) => row.billingClass !== 'paying').reduce((sum, row) => sum + row.busyHours, 0);
  const sessions = totals ? totals.sessionsSucceeded + totals.sessionsFailed : 0;

  return (
    <div className={classes.tiles}>
      <Tile label="Companies" value={formatCount(snapshot.companies)}>
        {split.join(' · ') || 'none measured yet'}
        {unbilled > 0 && <span className={classes.bad}> · {unbilled} not billed</span>}
      </Tile>
      <Tile label="People" value={formatCount(snapshot.members)}>
        active members
      </Tile>
      <Tile label="Projects" value={formatCount(snapshot.projects)}>
        active projects
      </Tile>
      <Tile
        label="Worker hours"
        value={totals ? formatHours(totals.workerHours) : '—'}
        delta={
          totals ? { field: 'workerHours', current: totals.workerHours, previous: previous?.workerHours } : undefined
        }
      >
        capacity offered by worker limits
      </Tile>
      <Tile
        label="Busy hours"
        value={totals ? formatHours(totals.busyHours) : '—'}
        delta={totals ? { field: 'busyHours', current: totals.busyHours, previous: previous?.busyHours } : undefined}
      >
        {totals && totals.busyHours > 0
          ? `${formatPercent(freeBusy / totals.busyHours)} not on a paid plan`
          : 'workers actually running'}
      </Tile>
      <Tile
        label="Successful sessions"
        value={totals ? formatCount(totals.sessionsSucceeded) : '—'}
        delta={
          totals
            ? { field: 'sessionsSucceeded', current: totals.sessionsSucceeded, previous: previous?.sessionsSucceeded }
            : undefined
        }
      >
        {sessions > 0
          ? `${formatCount(totals?.sessionsFailed ?? 0)} failed (${formatPercent((totals?.sessionsFailed ?? 0) / sessions)})`
          : 'no sessions ended'}
      </Tile>
    </div>
  );
}
