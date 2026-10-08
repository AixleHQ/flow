import { VisuallyHidden } from '@mantine/core';
import { IconArrowDown, IconArrowUp, IconArrowsSort } from '@tabler/icons-react';

import { type ListSort, nextListSort } from './listSort';
import classes from './SortableHeader.module.css';

interface SortableHeaderProps {
  label: string;
  field: string;
  sort: ListSort;
  onSort: (next: ListSort) => void;
}

/** A column header that sorts the list by its column; the arrow shows the active one and its direction. */
export function SortableHeader({ label, field, sort, onSort }: SortableHeaderProps) {
  const active = sort.field === field;
  const Icon = !active ? IconArrowsSort : sort.direction === 'desc' ? IconArrowDown : IconArrowUp;

  return (
    <button
      type="button"
      className={active ? `${classes.button} ${classes.active}` : classes.button}
      onClick={() => onSort(nextListSort(sort, field))}
    >
      {label}
      <Icon size={12} className={classes.icon} aria-hidden />
      {active && (
        <VisuallyHidden>{sort.direction === 'desc' ? ', sorted descending' : ', sorted ascending'}</VisuallyHidden>
      )}
    </button>
  );
}
