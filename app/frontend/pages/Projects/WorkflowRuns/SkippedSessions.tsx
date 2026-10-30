import { IconChevronRight } from '@tabler/icons-react';
import { useState } from 'react';

import { StatusTag } from 'shared/ui/sessions';

import classes from './SkippedSessions.module.css';

export interface SkippedSession {
  id: number;
  number: number;
  title: string;
  reason: string | null;
}

/** Consecutive sessions skipped before they started, folded into one row. */
export function SkippedSessions({ sessions }: { sessions: SkippedSession[] }) {
  const [open, setOpen] = useState(false);
  const first = sessions[0].number;
  const last = sessions[sessions.length - 1].number;
  const ordinal = first === last ? `Session ${first}` : `Sessions ${first}–${last}`;

  return (
    <section className={classes.group}>
      <button
        type="button"
        className={classes.top}
        aria-expanded={open}
        aria-label={`${open ? 'Collapse' : 'Expand'} skipped ${ordinal.toLowerCase()}`}
        onClick={() => setOpen((v) => !v)}
      >
        <span className={open ? `${classes.caret} ${classes.caretOpen}` : classes.caret}>
          <IconChevronRight size={14} />
        </span>
        <span className={classes.ordinal}>{ordinal}</span>
        <span className={classes.titles}>{sessions.map((s) => s.title).join(', ')}</span>
        <StatusTag state="skipped">{sessions.length === 1 ? 'Skipped' : `${sessions.length} skipped`}</StatusTag>
      </button>

      {open && (
        <ul className={classes.rows}>
          {sessions.map((s) => (
            <li className={classes.row} key={s.id}>
              <span className={classes.ordinal}>Session {s.number}</span>
              <span className={classes.rowBody}>
                <span className={classes.rowTitle}>{s.title}</span>
                {s.reason && <span className={classes.reason}>{s.reason}</span>}
              </span>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
