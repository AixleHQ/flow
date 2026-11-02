import classes from './Dashboard.module.css';
import { formatCount, formatWait } from './format';

export interface WaitRow {
  key: string;
  label: string;
  sessions: number;
  waited: number;
  p95: number | null;
}

/** One row per day or hour: how many of its sessions waited, as a bar, and its p95 wait. */
export default function WaitTable({ heading, rows }: { heading: string; rows: WaitRow[] }) {
  const most = Math.max(1, ...rows.map((row) => row.waited));

  return (
    <div className={classes.tableWrap}>
      <table className={classes.table}>
        <thead>
          <tr>
            <th scope="col">{heading}</th>
            <th scope="col" className={classes.waitedColumn}>
              Sessions that waited over 30 s
            </th>
            <th scope="col" className={classes.number}>
              p95 wait
            </th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={row.key}>
              <th scope="row">{row.label}</th>
              <td>
                <span className={classes.waitBar}>
                  <span className={classes.waitTrack} aria-hidden="true">
                    {row.waited > 0 && (
                      <span className={classes.waitFill} style={{ width: `${(row.waited / most) * 100}%` }} />
                    )}
                  </span>
                  {row.sessions ? `${formatCount(row.waited)} of ${formatCount(row.sessions)}` : 'no sessions'}
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
