import { useEffect, useId, useRef, useState, type ReactNode } from 'react';

import type { DayRange, TenantSummary } from './aggregate';
import classes from './Dashboard.module.css';
import { BILLING_LABELS, formatCount, formatPercent, formatWait, formatWorkers } from './format';
import type { CompanyBreakdown, WaitStats } from './types';
import WaitDays from './WaitDays';

const tenths = new Intl.NumberFormat('en-US', { maximumFractionDigits: 1 });

const FOCUSABLE = 'a[href], button:not([disabled]), summary, [tabindex]:not([tabindex="-1"])';

type State = { status: 'loading' } | { status: 'failed' } | { status: 'ready'; breakdown: CompanyBreakdown };

interface Props {
  tenant: TenantSummary;
  range: DayRange;
  /** The period as the dashboard names it, e.g. "Oct 1 – Oct 30, 2026". */
  span: string;
  onClose: () => void;
}

function Figure({ label, value, children }: { label: string; value: string; children?: ReactNode }) {
  return (
    <section className={classes.tile} aria-label={label}>
      <h4 className={classes.tileLabel}>{label}</h4>
      <p className={classes.tileValue}>{value}</p>
      {children && <p className={classes.tileNote}>{children}</p>}
    </section>
  );
}

const share = (part: number, whole: number) => (whole > 0 ? part / whole : null);

function Spread({ label, stats }: { label: string; stats: WaitStats }) {
  const points: [string, number | null][] = [
    ['Average', stats.average],
    ['Median', stats.p50],
    ['p90', stats.p90],
    ['p95', stats.p95],
    ['p99', stats.p99],
    ['Max', stats.max],
  ];
  return (
    <dl className={classes.spread} aria-label={label}>
      {points.map(([name, value]) => (
        <div key={name}>
          <dt>{name}</dt>
          <dd>{formatWait(value)}</dd>
        </div>
      ))}
    </dl>
  );
}

function Capacity({ tenant, breakdown }: { tenant: TenantSummary; breakdown: CompanyBreakdown }) {
  const { capacity, workerLimit, projectDefault } = breakdown;
  const limit = (
    <Figure label="Worker limit now" value={formatWorkers(workerLimit ?? Infinity)}>
      a project without its own limit gets {projectDefault}
    </Figure>
  );

  if (capacity.offeredHours === 0) {
    return (
      <div className={classes.tiles}>
        {limit}
        <p className={classes.sectionNote}>
          No worker limit in this period, so nothing capped the company and utilization does not apply. A session here
          waits only for its project&apos;s own limit — see Projects below.
        </p>
      </div>
    );
  }

  return (
    <div className={classes.tiles}>
      <Figure label="Utilization" value={formatPercent(tenant.utilization)}>
        busy ÷ worker hours, averaged over every hour of the period, nights included
      </Figure>
      <Figure label="Time at capacity" value={formatPercent(capacity.timeAtCapacity)}>
        of the {formatCount(capacity.offeredHours)} hours it had workers, every one was busy at once
      </Figure>
      <Figure
        label="Waits that began at capacity"
        value={formatPercent(share(capacity.waitedAtCapacity, capacity.waited))}
      >
        {capacity.waited
          ? `${formatCount(capacity.waitedAtCapacity)} of the ${formatCount(capacity.waited)} sessions that waited over 30 s in those hours joined while every worker was busy`
          : 'no session waited over 30 s in those hours'}
      </Figure>
      {limit}
    </div>
  );
}

function Breakdown({ tenant, breakdown }: { tenant: TenantSummary; breakdown: CompanyBreakdown }) {
  const { waits, runs, projects, days } = breakdown;

  return (
    <>
      <section className={classes.detailSection} aria-labelledby="detail-capacity">
        <h3 id="detail-capacity" className={classes.detailTitle}>
          Capacity
        </h3>
        <Capacity tenant={tenant} breakdown={breakdown} />
      </section>

      <section className={classes.detailSection} aria-labelledby="detail-sessions">
        <h3 id="detail-sessions" className={classes.detailTitle}>
          Queue wait per session
        </h3>
        <div className={classes.tiles}>
          <Figure label="Sessions" value={formatCount(waits.sessions)}>
            admitted in the period
          </Figure>
          <Figure label="Waited over 30 s" value={formatPercent(share(waits.waited, waits.sessions))}>
            {formatCount(waits.waited)} sessions
          </Figure>
          <Figure label="p95 wait" value={formatWait(waits.p95)}>
            95% of sessions started within this
          </Figure>
          <Figure label="p95 of those that waited" value={formatWait(waits.p95OfWaited)}>
            the same, counting only sessions that waited over 30 s
          </Figure>
        </div>
        <Spread label="Wait per session" stats={waits} />
        <p className={classes.sectionNote}>
          Already waiting when a session joined, from this company: {tenths.format(waits.aheadAverage ?? 0)} on average,{' '}
          {tenths.format(waits.aheadP95 ?? 0)} at p95, {formatCount(waits.aheadMax ?? 0)} at most.
        </p>
      </section>

      <section className={classes.detailSection} aria-labelledby="detail-days">
        <h3 id="detail-days" className={classes.detailTitle}>
          Waits by day
        </h3>
        <WaitDays days={days} />
      </section>

      <section className={classes.detailSection} aria-labelledby="detail-runs">
        <h3 id="detail-runs" className={classes.detailTitle}>
          Queue wait per workflow run
        </h3>
        {runs.runs > 0 ? (
          <>
            <p className={classes.sectionNote}>
              {formatCount(runs.runs)} runs, {tenths.format(runs.averageSteps ?? 0)}{' '}
              {runs.averageSteps === 1 ? 'step' : 'steps'} on average. A run queues again for every step, so its wait is
              the sum of its steps&apos;; {formatCount(runs.waited)} waited over 30 s in all.
            </p>
            <Spread label="Wait per workflow run" stats={runs} />
          </>
        ) : (
          <p className={classes.sectionNote}>No workflow run started a step in this period.</p>
        )}
      </section>

      <section className={classes.detailSection} aria-labelledby="detail-projects">
        <h3 id="detail-projects" className={classes.detailTitle}>
          Projects
        </h3>
        {projects.length ? (
          <div className={classes.tableWrap}>
            <table className={classes.table}>
              <thead>
                <tr>
                  <th scope="col">Project</th>
                  <th scope="col">Queue limit</th>
                  <th scope="col" className={classes.number}>
                    Sessions
                  </th>
                  <th scope="col" className={classes.number}>
                    Waited over 30 s
                  </th>
                  <th scope="col" className={classes.number}>
                    p95 wait
                  </th>
                  <th scope="col" className={classes.number}>
                    Max wait
                  </th>
                  <th scope="col" className={classes.number}>
                    Most ahead
                  </th>
                </tr>
              </thead>
              <tbody>
                {projects.map((project) => (
                  <tr key={project.id}>
                    <th scope="row" className={classes.tenant}>
                      {project.name}
                    </th>
                    <td>
                      {project.limit} {project.reserved ? 'reserved' : 'default'}
                    </td>
                    <td className={classes.number}>{formatCount(project.sessions)}</td>
                    <td className={classes.number}>{formatCount(project.waited)}</td>
                    <td className={classes.number}>{formatWait(project.p95)}</td>
                    <td className={classes.number}>{formatWait(project.max)}</td>
                    <td className={classes.number}>{formatCount(project.aheadMax)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : (
          <p className={classes.sectionNote}>No session of this company was admitted in this period.</p>
        )}
        <p className={classes.sectionNote}>
          A session waits for a free worker in its project — that project&apos;s reservation, or the default — and in
          the company as a whole. Most ahead is the longest line inside the project. Limits are as they stand now.
        </p>
      </section>
    </>
  );
}

/** One company over the dashboard's selected days, read from its admissions when opened. */
export default function CompanyDetail({ tenant, range, span, onClose }: Props) {
  const [state, setState] = useState<State>({ status: 'loading' });
  const dialog = useRef<HTMLDivElement>(null);
  const closeButton = useRef<HTMLButtonElement>(null);
  const titleId = useId();
  const billing = BILLING_LABELS[tenant.billingClass];

  useEffect(() => {
    const controller = new AbortController();
    const query = new URLSearchParams({ from: range.start, to: range.end });
    fetch(`/admin/dashboard/companies/${tenant.tenantId}.json?${query}`, {
      headers: { Accept: 'application/json' },
      signal: controller.signal,
    })
      .then((response) => {
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        return response.json() as Promise<CompanyBreakdown>;
      })
      .then((breakdown) => setState({ status: 'ready', breakdown }))
      .catch(() => {
        if (!controller.signal.aborted) setState({ status: 'failed' });
      });
    return () => controller.abort();
  }, [tenant.tenantId, range.start, range.end]);

  // Without Mantine on this page the dialog keeps focus itself: it takes it on
  // open, holds Tab inside, closes on Escape, and hands focus back on close.
  useEffect(() => {
    const opener = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const overflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    closeButton.current?.focus();

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        onClose();
        return;
      }
      if (event.key !== 'Tab' || !dialog.current) return;
      const focusable = Array.from(dialog.current.querySelectorAll<HTMLElement>(FOCUSABLE));
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };
    document.addEventListener('keydown', onKeyDown);
    return () => {
      document.removeEventListener('keydown', onKeyDown);
      document.body.style.overflow = overflow;
      opener?.focus();
    };
  }, [onClose]);

  return (
    <div
      className={classes.scrim}
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <div ref={dialog} className={classes.dialog} role="dialog" aria-modal="true" aria-labelledby={titleId}>
        <header className={classes.dialogHeader}>
          <div className={classes.dialogHeading}>
            <h2 id={titleId} className={classes.dialogTitle}>
              {tenant.name}
            </h2>
            <p className={classes.dialogMeta}>
              <span className={`${classes.badge} ${classes[billing.tone]}`}>{billing.label}</span>
              {span} · UTC · <a href={`/admin/companies/${tenant.tenantId}`}>Company record</a>
            </p>
          </div>
          <button ref={closeButton} type="button" className={classes.close} aria-label="Close" onClick={onClose}>
            ×
          </button>
        </header>

        <div className={classes.dialogBody}>
          {state.status === 'loading' && <p className={classes.sectionNote}>Reading this company&apos;s queue…</p>}
          {state.status === 'failed' && (
            <p className={classes.sectionNote} role="alert">
              The breakdown could not be loaded. Close this and open the company again.
            </p>
          )}
          {state.status === 'ready' && <Breakdown tenant={tenant} breakdown={state.breakdown} />}
        </div>
      </div>
    </div>
  );
}
