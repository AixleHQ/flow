import { useCallback, useMemo, useState, type ReactNode } from 'react';

import {
  comparisonRange,
  deltaOf,
  periodOf,
  periodsFor,
  rangeOf,
  summarize,
  todayOf,
  totalsOf,
  withP95,
  workersOf,
  type DayRange,
  type DeltaField,
  type Grain,
  type TenantSummary,
  type Totals,
} from './aggregate';
import CompanyDetail from './CompanyDetail';
import classes from './Dashboard.module.css';
import FilterBar from './FilterBar';
import { filterRows, isFiltered, NO_FILTERS, type Filters } from './filters';
import {
  ACCOUNT_STATUS_LABELS,
  ACCOUNT_TYPE_LABELS,
  BILLING_METHOD_LABELS,
  formatCount,
  formatHours,
  formatPercent,
  formatWait,
  formatWorkers,
} from './format';
import Tiles from './Tiles';
import type { BillingClass, DashboardData, DashboardPaths } from './types';
import { useTenantP95 } from './useTenantP95';

const UNBILLED: BillingClass[] = ['unlimited', 'no_customer'];

type SortKey = 'name' | 'createdAt' | 'accountStatus' | 'accountType' | 'billingMethod' | DeltaField;
type Direction = 'ascending' | 'descending';

const GRAINS: { grain: Grain; label: string }[] = [
  { grain: 'day', label: 'Day' },
  { grain: 'week', label: 'Week' },
  { grain: 'month', label: 'Month' },
  { grain: 'custom', label: 'Custom' },
];

const dateOf = (day: string) => new Date(`${day}T00:00:00Z`);
const monthLabel = new Intl.DateTimeFormat('en-US', { month: 'long', year: 'numeric', timeZone: 'UTC' });
const shortDay = new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' });
const longDay = new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric', year: 'numeric', timeZone: 'UTC' });
const weekday = new Intl.DateTimeFormat('en-US', {
  weekday: 'short',
  month: 'short',
  day: 'numeric',
  year: 'numeric',
  timeZone: 'UTC',
});
const instant = new Intl.DateTimeFormat('en-US', {
  month: 'short',
  day: 'numeric',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
  timeZone: 'UTC',
});

const spanOf = (range: DayRange) =>
  range.start === range.end
    ? weekday.format(dateOf(range.start))
    : `${shortDay.format(dateOf(range.start))} – ${longDay.format(dateOf(range.end))}`;

function periodLabel(grain: Grain, period: string, current: string) {
  const suffix = period === current ? ' (current)' : '';
  if (grain === 'month') return `${monthLabel.format(dateOf(`${period}-01`))}${suffix}`;
  if (grain === 'week') return `Week of ${longDay.format(dateOf(period))}${suffix}`;
  return weekday.format(dateOf(period));
}

const accountStatusOf = (row: TenantSummary) => (row.accountStatus ? ACCOUNT_STATUS_LABELS[row.accountStatus] : null);
const accountTypeOf = (row: TenantSummary) => (row.accountType ? ACCOUNT_TYPE_LABELS[row.accountType] : '—');
const billingMethodOf = (row: TenantSummary) => (row.billingMethod ? BILLING_METHOD_LABELS[row.billingMethod] : '—');

function sortValue(row: TenantSummary, key: SortKey): number | string {
  if (key === 'name') return row.name.toLowerCase();
  if (key === 'createdAt') return row.createdAt ? Date.parse(row.createdAt) : -Infinity;
  if (key === 'accountStatus') return accountStatusOf(row)?.label ?? '—';
  if (key === 'accountType') return accountTypeOf(row);
  if (key === 'billingMethod') return billingMethodOf(row);
  // Missing values sort below every real one.
  return row[key] ?? -Infinity;
}

interface CellContext {
  previous: TenantSummary | undefined;
  p95Loading: boolean;
}

interface Column {
  key: SortKey;
  label: string;
  cell: (row: TenantSummary, context: CellContext) => ReactNode;
  numeric?: boolean;
  total?: keyof Totals;
}

const deltaCell = (field: DeltaField, value: number | null, previous: number | null | undefined) => {
  const change = deltaOf(field, value, previous ?? null);
  const tone = change && change.tone !== 'neutral' ? classes[change.tone] : '';
  return <span className={`${classes.delta} ${tone}`}>{change?.text ?? '—'}</span>;
};

const COLUMNS: Column[] = [
  { key: 'name', label: 'Company', cell: (row) => row.name },
  {
    key: 'utilization',
    label: 'Utilization',
    numeric: true,
    cell: (row, { previous }) => (
      <>
        <span className={classes.utilization}>
          <span className={classes.bar} aria-hidden="true">
            <span className={classes.fill} style={{ width: `${Math.min(100, (row.utilization ?? 0) * 100)}%` }} />
          </span>
          {formatPercent(row.utilization)}
        </span>
        {deltaCell('utilization', row.utilization, previous?.utilization)}
      </>
    ),
  },
  {
    key: 'avgWaitSeconds',
    label: 'Average wait',
    numeric: true,
    cell: (row, { previous }) => (
      <>
        {formatWait(row.avgWaitSeconds)}
        {deltaCell('avgWaitSeconds', row.avgWaitSeconds, previous?.avgWaitSeconds)}
      </>
    ),
  },
  {
    key: 'p95WaitSeconds',
    label: 'p95 wait',
    numeric: true,
    cell: (row, { previous, p95Loading }) => (
      <>
        {p95Loading ? '…' : formatWait(row.p95WaitSeconds)}
        {deltaCell('p95WaitSeconds', row.p95WaitSeconds, previous?.p95WaitSeconds)}
      </>
    ),
  },
  {
    key: 'createdAt',
    label: 'Account created',
    cell: (row) => (row.createdAt ? longDay.format(new Date(row.createdAt)) : '—'),
  },
  {
    key: 'accountStatus',
    label: 'Account status',
    cell: (row) => {
      const status = accountStatusOf(row);
      if (!status) return '—';
      return <span className={`${classes.badge} ${classes[status.tone]}`}>{status.label}</span>;
    },
  },
  { key: 'accountType', label: 'Account type', cell: (row) => accountTypeOf(row) },
  { key: 'billingMethod', label: 'Billing method', cell: (row) => billingMethodOf(row) },
  {
    key: 'workerHours',
    label: 'Worker hours',
    numeric: true,
    total: 'workerHours',
    cell: (row, { previous }) => (
      <>
        {formatHours(row.workerHours)}
        {deltaCell('workerHours', row.workerHours, previous?.workerHours)}
      </>
    ),
  },
  {
    key: 'busyHours',
    label: 'Busy hours',
    numeric: true,
    total: 'busyHours',
    cell: (row, { previous }) => (
      <>
        {formatHours(row.busyHours)}
        {deltaCell('busyHours', row.busyHours, previous?.busyHours)}
      </>
    ),
  },
  {
    key: 'minWorkers',
    label: 'Min workers',
    numeric: true,
    cell: (row, { previous }) => (
      <>
        {formatWorkers(row.minWorkers)}
        {deltaCell('minWorkers', row.minWorkers, previous?.minWorkers)}
      </>
    ),
  },
  {
    key: 'maxWorkers',
    label: 'Max workers',
    numeric: true,
    cell: (row, { previous }) => (
      <>
        {formatWorkers(row.maxWorkers)}
        {deltaCell('maxWorkers', row.maxWorkers, previous?.maxWorkers)}
      </>
    ),
  },
  {
    key: 'peakWorkers',
    label: 'Peak workers',
    numeric: true,
    cell: (row, { previous }) => (
      <>
        {formatWorkers(row.peakWorkers)}
        {deltaCell('peakWorkers', row.peakWorkers, previous?.peakWorkers)}
      </>
    ),
  },
  {
    key: 'sessionsSucceeded',
    label: 'Successful sessions',
    numeric: true,
    total: 'sessionsSucceeded',
    cell: (row, { previous }) => (
      <>
        {formatCount(row.sessionsSucceeded)}
        {deltaCell('sessionsSucceeded', row.sessionsSucceeded, previous?.sessionsSucceeded)}
      </>
    ),
  },
  {
    key: 'sessionsFailed',
    label: 'Failed sessions',
    numeric: true,
    total: 'sessionsFailed',
    cell: (row, { previous }) => (
      <>
        {formatCount(row.sessionsFailed)}
        {deltaCell('sessionsFailed', row.sessionsFailed, previous?.sessionsFailed)}
      </>
    ),
  },
];

const [COMPANY_COLUMN, ...VALUE_COLUMNS] = COLUMNS;

interface Props {
  data: DashboardData;
  paths: DashboardPaths;
  now?: Date;
  timeZone?: string;
}

export default function Dashboard({
  data,
  paths,
  now = new Date(),
  timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone,
}: Props) {
  const today = todayOf(now);
  const [grain, setGrain] = useState<Grain>('week');
  const [chosenPeriod, setChosenPeriod] = useState<string | null>(null);
  const [custom, setCustom] = useState<DayRange>({ start: `${today.slice(0, 7)}-01`, end: today });
  const [filters, setFilters] = useState<Filters>(NO_FILTERS);
  const [sort, setSort] = useState<{ key: SortKey; direction: Direction }>({ key: 'name', direction: 'ascending' });
  const [opened, setOpened] = useState<TenantSummary | null>(null);
  const closeDetail = useCallback(() => setOpened(null), []);

  const view = useMemo(() => {
    const lastDataDay = data.days.reduce((last, row) => (row.day > last ? row.day : last), '');
    let periods: string[] = [];
    let period = '';
    let range: DayRange;

    if (grain === 'custom') {
      range = custom.start <= custom.end ? custom : { start: custom.end, end: custom.start };
    } else {
      periods = periodsFor(grain, data.days);
      const current = periodOf(grain, today);
      period =
        chosenPeriod && periods.includes(chosenPeriod)
          ? chosenPeriod
          : periods.includes(current)
            ? current
            : (periods[0] ?? current);
      range = rangeOf(grain, period);
    }

    const rows = summarize(data.days, data.tenants, range);
    const dataStart = rows.reduce((first, row) => (!first || row.firstDay < first ? row.firstDay : first), '');
    const dataEnd =
      grain === 'custom' ? lastDataDay : rows.reduce((last, row) => (row.lastDay > last ? row.lastDay : last), '');
    const comparison = rows.length ? comparisonRange(grain, range, dataEnd) : null;
    const previous = comparison ? summarize(data.days, data.tenants, comparison) : [];

    return {
      periods,
      period,
      range,
      rows,
      dataStart,
      dataEnd,
      comparison,
      previous,
      previousByTenant: new Map(previous.map((row) => [row.tenantId, row])),
    };
  }, [data, grain, chosenPeriod, custom, today]);

  const hasData = data.days.length > 0;
  const currentP95 = useTenantP95(paths.base, hasData ? view.range : null);
  const previousP95 = useTenantP95(paths.base, view.previousByTenant.size ? view.comparison : null);
  const rows = useMemo(
    () => withP95(view.rows, currentP95.status === 'ready' ? currentP95.p95 : undefined),
    [view.rows, currentP95],
  );
  const previousByTenant = useMemo(() => {
    const previous = withP95(
      Array.from(view.previousByTenant.values()),
      previousP95.status === 'ready' ? previousP95.p95 : undefined,
    );
    return new Map(previous.map((row) => [row.tenantId, row]));
  }, [view.previousByTenant, previousP95]);

  const filtering = isFiltered(filters);
  const filtered = useMemo(() => filterRows(rows, filters), [rows, filters]);
  const totals = useMemo(() => totalsOf(filtered), [filtered]);
  const previousTotals = useMemo(() => totalsOf(filterRows(view.previous, filters)), [view.previous, filters]);
  const workers = useMemo(
    () => workersOf(data.days, view.range, new Set(filtered.map((row) => row.tenantId))),
    [data.days, view.range, filtered],
  );
  const previousWorkers = useMemo(() => {
    if (!view.comparison) return null;
    const companies = new Set(filterRows(view.previous, filters).map((row) => row.tenantId));
    return workersOf(data.days, view.comparison, companies);
  }, [data.days, view.comparison, view.previous, filters]);

  const visible = useMemo(() => {
    const direction = sort.direction === 'ascending' ? 1 : -1;
    return [...filtered].sort((a, b) => {
      const left = sortValue(a, sort.key);
      const right = sortValue(b, sort.key);
      const order =
        typeof left === 'number' && typeof right === 'number'
          ? left - right
          : String(left).localeCompare(String(right));
      return order * direction;
    });
  }, [filtered, sort]);

  const latestClass = useMemo(() => {
    const latest = new Map<number, BillingClass>();
    for (const row of data.days) latest.set(row.companyId, row.billingClass);
    return latest;
  }, [data.days]);

  const unbilledAmong = (ids: number[]) =>
    ids.filter((id) => {
      const latest = latestClass.get(id);
      return latest !== undefined && UNBILLED.includes(latest);
    }).length;
  const companies = filtering
    ? {
        count: filtered.length,
        accounts: filtered,
        unbilled: unbilledAmong(filtered.map((row) => row.tenantId)),
      }
    : {
        count: data.snapshot.companies,
        accounts: data.tenants,
        unbilled: unbilledAmong(Array.from(latestClass.keys())),
      };

  const tiles = (
    <Tiles
      snapshot={data.snapshot}
      companies={companies}
      filtered={filtering}
      rows={filtered}
      totals={totals}
      previous={previousTotals}
      workers={workers}
      previousWorkers={previousWorkers}
    />
  );

  if (!data.days.length) {
    return (
      <div className={classes.root}>
        {tiles}
        <p className={classes.empty}>
          No usage has been measured yet. Each hour is measured ten minutes after it closes.
        </p>
      </div>
    );
  }

  const index = view.periods.indexOf(view.period);
  const current = grain === 'custom' ? '' : periodOf(grain, today);

  let span = 'No activity in this period';
  if (view.rows.length) {
    span = spanOf(grain === 'custom' ? view.range : { start: view.dataStart, end: view.dataEnd });
    if (grain === 'custom') span += ' · custom range';
    else if (grain !== 'day' && view.period === current) span += ' · to date';
    const shown = filtering ? `${filtered.length} of ${view.rows.length}` : `${view.rows.length}`;
    span += ` · ${shown} ${view.rows.length === 1 ? 'company' : 'companies'}`;
  }
  const compare = view.comparison
    ? view.previousByTenant.size
      ? `Change vs ${spanOf(view.comparison)}`
      : `No data for the previous period (${spanOf(view.comparison)})`
    : '';

  const toggleSort = (key: SortKey) =>
    setSort((was) =>
      was.key === key
        ? { key, direction: was.direction === 'ascending' ? 'descending' : 'ascending' }
        : { key, direction: key === 'name' ? 'ascending' : 'descending' },
    );

  const footerCell = (totals: Totals, column: Column) => {
    const field = column.total;
    if (!field) return <td key={column.key} />;
    return (
      <td key={column.key} className={classes.number}>
        {field === 'workerHours' || field === 'busyHours' ? formatHours(totals[field]) : formatCount(totals[field])}
        {deltaCell(field, totals[field], previousTotals?.[field])}
      </td>
    );
  };

  return (
    <div className={classes.root}>
      <div className={classes.toolbar}>
        <div className={classes.segmented} role="group" aria-label="Period length">
          {GRAINS.map((option) => (
            <button
              key={option.grain}
              type="button"
              className={classes.segment}
              aria-pressed={grain === option.grain}
              onClick={() => {
                setGrain(option.grain);
                setChosenPeriod(null);
              }}
            >
              {option.label}
            </button>
          ))}
        </div>

        {grain === 'custom' ? (
          <div className={classes.dates}>
            <label className={classes.field}>
              From
              <input
                type="date"
                value={custom.start}
                max={today}
                onChange={(event) => event.target.value && setCustom({ ...custom, start: event.target.value })}
              />
            </label>
            <label className={classes.field}>
              To
              <input
                type="date"
                value={custom.end}
                max={today}
                onChange={(event) => event.target.value && setCustom({ ...custom, end: event.target.value })}
              />
            </label>
          </div>
        ) : (
          <div className={classes.periodNav}>
            <button
              type="button"
              className={classes.navButton}
              aria-label="Previous period"
              disabled={index < 0 || index >= view.periods.length - 1}
              onClick={() => setChosenPeriod(view.periods[index + 1])}
            >
              ‹
            </button>
            <select
              className={classes.select}
              aria-label="Period"
              value={view.period}
              onChange={(event) => setChosenPeriod(event.target.value)}
            >
              {view.periods.map((period) => (
                <option key={period} value={period}>
                  {periodLabel(grain, period, current)}
                </option>
              ))}
            </select>
            <button
              type="button"
              className={classes.navButton}
              aria-label="Next period"
              disabled={index <= 0}
              onClick={() => setChosenPeriod(view.periods[index - 1])}
            >
              ›
            </button>
          </div>
        )}

        <input
          type="search"
          className={classes.search}
          aria-label="Search companies"
          placeholder="Search companies"
          value={filters.query}
          onChange={(event) => setFilters({ ...filters, query: event.target.value })}
        />
      </div>

      <FilterBar filters={filters} today={today} onChange={setFilters} />

      <p className={classes.span}>{span}</p>
      {compare && <p className={classes.compare}>{compare}</p>}
      {currentP95.status === 'failed' && (
        <p className={classes.compare} role="alert">
          The p95 wait could not be loaded; reload the page to try again.
        </p>
      )}

      {tiles}

      <h2 className={classes.sectionTitle}>Companies</h2>

      <div className={classes.tableWrap}>
        <table className={classes.table}>
          <thead>
            <tr>
              {COLUMNS.map((column) => (
                <th key={column.key} aria-sort={sort.key === column.key ? sort.direction : 'none'}>
                  <button type="button" onClick={() => toggleSort(column.key)}>
                    {column.label}
                  </button>
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {visible.length === 0 ? (
              <tr>
                <td colSpan={COLUMNS.length} className={classes.emptyRow}>
                  {filtering ? 'No companies match the search and filters.' : 'No company activity in this period.'}
                </td>
              </tr>
            ) : (
              visible.map((row) => {
                const context = {
                  previous: previousByTenant.get(row.tenantId),
                  p95Loading: currentP95.status === 'loading',
                };
                return (
                  <tr key={row.tenantId}>
                    <th scope="row" className={classes.tenant}>
                      <button type="button" className={classes.tenantButton} onClick={() => setOpened(row)}>
                        {COMPANY_COLUMN.cell(row, context)}
                      </button>
                    </th>
                    {VALUE_COLUMNS.map((column) => (
                      <td key={column.key} className={column.numeric ? classes.number : undefined}>
                        {column.cell(row, context)}
                      </td>
                    ))}
                  </tr>
                );
              })
            )}
          </tbody>
          {totals && (
            <tfoot>
              <tr>
                <th scope="row">{filtering ? 'Total, companies shown' : 'Total, all companies'}</th>
                {VALUE_COLUMNS.map((column) => footerCell(totals, column))}
              </tr>
            </tfoot>
          )}
        </table>
      </div>

      <p className={classes.note}>
        Worker hours are the capacity a company was offered — its worker limit over time, which is what a paying company
        is billed for; for the time a company has no limit they are its busy hours, so that time shows as fully used.
        Busy hours are the time its workers actually held a session; utilization is busy ÷ worker hours. Min and max
        workers are the limit (∞ when none was set); peak workers is the most held at once. Average workers in the tiles
        is the workers offered over the period&apos;s measured hours, which is what an invoice charges for, split by
        each day&apos;s billing class; a company with no limit is offered none, so it counts at its peak workers. Wait
        time is how long a session queued before a worker took it; 95% of the period&apos;s sessions started within the
        p95 wait. Account status, account type and billing method are each company&apos;s as it stands now, whatever the
        period; a company with no billing method is one nobody invoices — managed by Aixle, not paying yet, or
        self-hosted. Account created is the UTC day the company was created. The search and the filters narrow the
        table, its total and the tiles to the companies that match, all but People and Projects, which always count the
        whole platform. “Not billed” in the Companies and Average workers tiles counts companies, or their workers, that
        run free without being managed, which should never happen. Days are UTC and weeks run Monday to Sunday. The
        small figure under each value is the change from the previous period; a period still in progress is compared
        with the same number of days of the one before.
        {data.measuredThrough && ` Measured through ${instant.format(new Date(data.measuredThrough))} UTC.`} Open a
        company for its queue in detail: wait percentiles, how many were already waiting, its projects and its hours.
      </p>

      {opened && (
        <CompanyDetail
          key={`${opened.tenantId}:${view.range.start}:${view.range.end}`}
          paths={paths}
          tenant={opened}
          range={view.range}
          span={spanOf(view.range)}
          timeZone={timeZone}
          onClose={closeDetail}
        />
      )}
    </div>
  );
}
