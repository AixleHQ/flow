import classes from './Dashboard.module.css';
import { formatCount, formatWait } from './format';

export interface WaitRow {
  key: string;
  label: string;
  sessions: number;
  waited: number;
  p95: number | null;
}

interface Props {
  heading: string;
  rows: WaitRow[];
  /** Makes each row's label a toggle; `selected` is the key of the row pressed. */
  onSelect?: (key: string) => void;
  selected?: string | null;
}

/** One row per day or hour: how many of its sessions waited, as a bar, and its p95 wait. */
export default function WaitTable({ heading, rows, onSelect, selected = null }: Props) {
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
            <tr key={row.key} className={row.key === selected ? classes.selectedRow : undefined}>
              <th scope="row">
                {onSelect ? (
                  <button
                    type="button"
                    className={classes.rowButton}
                    aria-pressed={row.key === selected}
                    onClick={() => onSelect(row.key)}
                  >
                    {row.label}
                  </button>
                ) : (
                  row.label
                )}
              </th>
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
