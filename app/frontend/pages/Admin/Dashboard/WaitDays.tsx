import classes from './Dashboard.module.css';
import { formatCount, formatWait } from './format';
import type { WaitDay } from './types';

const dayLabel = new Intl.DateTimeFormat('en-US', {
  weekday: 'short',
  month: 'short',
  day: 'numeric',
  timeZone: 'UTC',
});

/** One row per day of the period that had sessions: how many of them waited, as a bar, and that day's p95 wait. */
export default function WaitDays({ days }: { days: WaitDay[] }) {
  if (!days.length) return <p className={classes.sectionNote}>No session of this company started in this period.</p>;

  const most = Math.max(1, ...days.map((row) => row.waited));

  return (
    <div className={classes.tableWrap}>
      <table className={classes.table}>
        <thead>
          <tr>
            <th scope="col">Day (UTC)</th>
            <th scope="col" className={classes.waitedColumn}>
              Sessions that waited over 30 s
            </th>
            <th scope="col" className={classes.number}>
              p95 wait
            </th>
          </tr>
        </thead>
        <tbody>
          {days.map((row) => (
            <tr key={row.day}>
              <th scope="row">{dayLabel.format(new Date(`${row.day}T00:00:00Z`))}</th>
              <td>
                <span className={classes.dayBar}>
                  <span className={classes.dayTrack} aria-hidden="true">
                    {row.waited > 0 && (
                      <span className={classes.dayFill} style={{ width: `${(row.waited / most) * 100}%` }} />
                    )}
                  </span>
                  {formatCount(row.waited)} of {formatCount(row.sessions)}
                </span>
              </td>
              <td className={classes.number}>{formatWait(row.p95)}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
