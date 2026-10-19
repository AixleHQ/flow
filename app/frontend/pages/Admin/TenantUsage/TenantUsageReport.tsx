import { useMemo, useState } from 'react';

import {
  comparisonRange,
  deltaOf,
  periodOf,
  periodsFor,
  rangeOf,
  summarize,
  todayOf,
  totalsOf,
  type DayRange,
  type DeltaField,
  type Grain,
  type TenantSummary,
  type Totals,
} from './aggregate';
import { BILLING_LABELS, formatCount, formatHours, formatPercent, formatWait, formatWorkers } from './format';
import classes from './TenantUsageReport.module.css';
import type { TenantUsageData } from './types';

type SortKey = 'name' | 'billingClass' | DeltaField;
type Direction = 'ascending' | 'descending';

interface Column {
  key: SortKey;
  label: string;
}

const COLUMNS: Column[] = [
  { key: 'name', label: 'Tenant' },
  { key: 'billingClass', label: 'Billing' },
  { key: 'workerHours', label: 'Worker hours' },
  { key: 'busyHours', label: 'Busy hours' },
  { key: 'minWorkers', label: 'Min workers' },
  { key: 'maxWorkers', label: 'Max workers' },
  { key: 'peakWorkers', label: 'Peak workers' },
  { key: 'utilization', label: 'Utilization' },
  { key: 'avgWaitSeconds', label: 'Average wait' },
  { key: 'maxWaitSeconds', label: 'Max wait' },
  { key: 'sessionsSucceeded', label: 'Successful sessions' },
  { key: 'sessionsFailed', label: 'Failed sessions' },
];

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

function sortValue(row: TenantSummary, key: SortKey): number | string {
  if (key === 'name') return row.name.toLowerCase();
  if (key === 'billingClass') return BILLING_LABELS[row.billingClass].label;
  // Missing values sort below every real one.
  return row[key] ?? -Infinity;
}

interface Props {
  data: TenantUsageData;
  now?: Date;
}

export default function TenantUsageReport({ data, now = new Date() }: Props) {
  const today = todayOf(now);
  const [grain, setGrain] = useState<Grain>('month');
  const [chosenPeriod, setChosenPeriod] = useState<string | null>(null);
  const [custom, setCustom] = useState<DayRange>({ start: `${today.slice(0, 7)}-01`, end: today });
  const [query, setQuery] = useState('');
  const [sort, setSort] = useState<{ key: SortKey; direction: Direction }>({ key: 'name', direction: 'ascending' });

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
      previousByTenant: new Map(previous.map((row) => [row.tenantId, row])),
      totals: totalsOf(rows),
      previousTotals: totalsOf(previous),
    };
  }, [data, grain, chosenPeriod, custom, today]);

  const visible = useMemo(() => {
    const needle = query.trim().toLowerCase();
    const filtered = needle ? view.rows.filter((row) => row.name.toLowerCase().includes(needle)) : view.rows;
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
  }, [view.rows, query, sort]);

  if (!data.days.length) {
    return (
      <p className={classes.empty}>
        No usage has been measured yet. Each hour is measured ten minutes after it closes.
      </p>
    );
  }

  const index = view.periods.indexOf(view.period);
  const current = grain === 'custom' ? '' : periodOf(grain, today);

  let span = 'No activity in this period';
  if (view.rows.length) {
    span = spanOf(grain === 'custom' ? view.range : { start: view.dataStart, end: view.dataEnd });
    if (grain === 'custom') span += ' · custom range';
    else if (grain !== 'day' && view.period === current) span += ' · to date';
    span += ` · ${view.rows.length} ${view.rows.length === 1 ? 'tenant' : 'tenants'}`;
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

  const delta = (field: DeltaField, value: number | null, previous: number | null | undefined) => {
    const change = deltaOf(field, value, previous ?? null);
    const tone = change && change.tone !== 'neutral' ? classes[change.tone] : '';
    return <span className={`${classes.delta} ${tone}`}>{change?.text ?? '—'}</span>;
  };

  const totalCell = (totals: Totals, field: keyof Totals) => (
    <td className={classes.number}>
      {field === 'workerHours' || field === 'busyHours' ? formatHours(totals[field]) : formatCount(totals[field])}
      {delta(field, totals[field], view.previousTotals?.[field])}
    </td>
  );

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
          aria-label="Search tenants"
          placeholder="Search tenants"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
        />
      </div>

      <p className={classes.span}>{span}</p>
      {compare && <p className={classes.compare}>{compare}</p>}

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
                  {query ? 'No tenants match that search.' : 'No tenant activity in this period.'}
                </td>
              </tr>
            ) : (
              visible.map((row) => {
                const previous = view.previousByTenant.get(row.tenantId);
                const billing = BILLING_LABELS[row.billingClass];
                return (
                  <tr key={row.tenantId}>
                    <th scope="row" className={classes.tenant}>
                      <a href={`/admin/companies/${row.tenantId}`}>{row.name}</a>
                    </th>
                    <td>
                      <span className={`${classes.badge} ${classes[billing.tone]}`}>{billing.label}</span>
                    </td>
                    <td className={classes.number}>
                      {formatHours(row.workerHours)}
                      {delta('workerHours', row.workerHours, previous?.workerHours)}
                    </td>
                    <td className={classes.number}>
                      {formatHours(row.busyHours)}
                      {delta('busyHours', row.busyHours, previous?.busyHours)}
                    </td>
                    <td className={classes.number}>
                      {formatWorkers(row.minWorkers)}
                      {delta('minWorkers', row.minWorkers, previous?.minWorkers)}
                    </td>
                    <td className={classes.number}>
                      {formatWorkers(row.maxWorkers)}
                      {delta('maxWorkers', row.maxWorkers, previous?.maxWorkers)}
                    </td>
                    <td className={classes.number}>
                      {formatWorkers(row.peakWorkers)}
                      {delta('peakWorkers', row.peakWorkers, previous?.peakWorkers)}
                    </td>
                    <td className={classes.number}>
                      <span className={classes.utilization}>
                        <span className={classes.bar} aria-hidden="true">
                          <span
                            className={classes.fill}
                            style={{ width: `${Math.min(100, (row.utilization ?? 0) * 100)}%` }}
                          />
                        </span>
                        {formatPercent(row.utilization)}
                      </span>
                      {delta('utilization', row.utilization, previous?.utilization)}
                    </td>
                    <td className={classes.number}>
                      {formatWait(row.avgWaitSeconds)}
                      {delta('avgWaitSeconds', row.avgWaitSeconds, previous?.avgWaitSeconds)}
                    </td>
                    <td className={classes.number}>
                      {formatWait(row.maxWaitSeconds)}
                      {delta('maxWaitSeconds', row.maxWaitSeconds, previous?.maxWaitSeconds)}
                    </td>
                    <td className={classes.number}>
                      {formatCount(row.sessionsSucceeded)}
                      {delta('sessionsSucceeded', row.sessionsSucceeded, previous?.sessionsSucceeded)}
                    </td>
                    <td className={classes.number}>
                      {formatCount(row.sessionsFailed)}
                      {delta('sessionsFailed', row.sessionsFailed, previous?.sessionsFailed)}
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
          {view.totals && (
            <tfoot>
              <tr>
                <th scope="row">Total, all tenants</th>
                <td />
                {totalCell(view.totals, 'workerHours')}
                {totalCell(view.totals, 'busyHours')}
                <td />
                <td />
                <td />
                <td />
                <td />
                <td />
                {totalCell(view.totals, 'sessionsSucceeded')}
                {totalCell(view.totals, 'sessionsFailed')}
              </tr>
            </tfoot>
          )}
        </table>
      </div>

      <p className={classes.note}>
        Worker hours are the capacity a tenant was offered — its worker limit over time, which is what a paying tenant
        is billed for. Busy hours are the time its workers actually held a session; utilization is busy ÷ worker hours,
        and has no value for a tenant without a limit. Min and max workers are the limit (∞ when none was set); peak
        workers is the most held at once. Wait time is how long a session queued before a worker took it. Billing shows
        whether the tenant&apos;s usage is billed and, when it is not, why. Days are UTC and weeks run Monday to Sunday.
        The small figure under each value is the change from the previous period; a period still in progress is compared
        with the same number of days of the one before.
        {data.measuredThrough && ` Measured through ${instant.format(new Date(data.measuredThrough))} UTC.`}
      </p>
    </div>
  );
}
