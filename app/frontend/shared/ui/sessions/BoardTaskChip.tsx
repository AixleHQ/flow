import { Link } from '@inertiajs/react';
import { Tooltip } from '@mantine/core';

import classes from './BoardTaskChip.module.css';

export interface BoardTaskRef {
  id: number;
  title: string;
  archived: boolean;
}

interface BoardTaskChipProps {
  projectId: number;
  boardTask: BoardTaskRef | null | undefined;
  /** List rows truncate the title; detail headers show the full string. */
  truncate?: boolean;
}

/**
 * Compact link to the board card that started a run. Renders nothing when the
 * run has no task (standalone / unbound / deleted).
 */
export function BoardTaskChip({ projectId, boardTask, truncate = false }: BoardTaskChipProps) {
  if (!boardTask) return null;

  const label = `#${boardTask.id} ${boardTask.title}`;
  const href = `/company/projects/${projectId}/board?task=${boardTask.id}`;

  const link = (
    <Link
      href={href}
      className={truncate ? `${classes.chip} ${classes.truncate}` : classes.chip}
      aria-label={`Open board task ${label}`}
      onClick={(e) => e.stopPropagation()}
    >
      <span className={classes.id}>#{boardTask.id}</span>
      <span className={classes.title}>{boardTask.title}</span>
    </Link>
  );

  if (!truncate) return link;

  return (
    <Tooltip label={label} withArrow multiline maw={360}>
      {link}
    </Tooltip>
  );
}
