import type { ReactNode } from 'react';

import { deltaOf, type DeltaField, type TenantSummary, type Totals } from './aggregate';
import classes from './Dashboard.module.css';
import { formatCount, formatHours, formatPercent } from './format';
import type { AccountStatus, AccountType, BillingMethod, Snapshot } from './types';

interface Account {
  accountStatus: AccountStatus | null;
  accountType: AccountType | null;
  billingMethod: BillingMethod | null;
}

interface Props {
  snapshot: Snapshot;
  /**
   * The companies the Companies tile counts, split by the same account columns
   * as the table, and how many ran their latest hour unbilled.
   */
  companies: { count: number; accounts: Account[]; unbilled: number };
  /** Whether filters narrow the tiles; People and Projects always count the whole platform. */
  filtered: boolean;
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

type AccountGroup = 'paying' | 'trial' | 'trial expired' | 'pending' | 'locked' | 'canceled' | 'managed';

const ACCOUNT_GROUPS: AccountGroup[] = ['paying', 'trial', 'trial expired', 'pending', 'locked', 'canceled', 'managed'];

const GROUP_BY_STATUS: Partial<Record<AccountStatus, AccountGroup>> = {
  trial_active: 'trial',
  trial_expired: 'trial expired',
  pending_activation: 'pending',
  locked_nonpayment: 'locked',
  canceled: 'canceled',
};

// An active customer nobody invoices is not paying, whatever its status says:
// every company of a self-hosted installation reads that way.
function groupOf({ accountStatus, accountType, billingMethod }: Account): AccountGroup | null {
  if (!accountStatus || accountStatus === 'inactive') return null;
  if (accountType === 'managed') return 'managed';
  if (accountStatus === 'active_customer') return billingMethod ? 'paying' : null;
  return GROUP_BY_STATUS[accountStatus] ?? null;
}

/** The platform's size as it stands, then what the selected period used. */
export default function Tiles({ snapshot, companies, filtered, rows, totals, previous }: Props) {
  const groups = companies.accounts.map(groupOf);
  const split = ACCOUNT_GROUPS.flatMap((group) => {
    const n = groups.filter((each) => each === group).length;
    return n ? [`${n} ${group}`] : [];
  });
  const { unbilled } = companies;
  const freeBusy = rows.filter((row) => row.billingClass !== 'paying').reduce((sum, row) => sum + row.busyHours, 0);
  const sessions = totals ? totals.sessionsSucceeded + totals.sessionsFailed : 0;

  return (
    <div className={classes.tiles}>
      <Tile label="Companies" value={formatCount(companies.count)}>
        {split.join(' · ') || (filtered ? 'none match the filters' : 'none measured yet')}
        {unbilled > 0 && <span className={classes.bad}> · {unbilled} not billed</span>}
      </Tile>
      <Tile label="People" value={formatCount(snapshot.members)}>
        {filtered ? 'active members, all companies' : 'active members'}
      </Tile>
      <Tile label="Projects" value={formatCount(snapshot.projects)}>
        {filtered ? 'active projects, all companies' : 'active projects'}
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
