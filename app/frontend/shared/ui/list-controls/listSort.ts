export type SortDirection = 'asc' | 'desc';

export interface ListSort {
  field: string;
  direction: SortDirection;
}

export const DEFAULT_LIST_SORT: ListSort = { field: 'created_at', direction: 'desc' };

/** Ransack's `q[s]` ("cost_cents desc"), as the server echoes it back. */
export function parseListSort(value: string | null | undefined): ListSort {
  const [field, direction] = (value ?? '').trim().split(/\s+/);
  if (!field) return DEFAULT_LIST_SORT;
  return { field, direction: direction === 'asc' ? 'asc' : 'desc' };
}

export function formatListSort({ field, direction }: ListSort): string {
  return `${field} ${direction}`;
}

export function isDefaultListSort(sort: ListSort): boolean {
  return sort.field === DEFAULT_LIST_SORT.field && sort.direction === DEFAULT_LIST_SORT.direction;
}

/** A newly picked column starts highest-first — the most expensive, the longest; the active one flips. */
export function nextListSort(current: ListSort, field: string): ListSort {
  if (current.field !== field) return { field, direction: 'desc' };
  return { field, direction: current.direction === 'desc' ? 'asc' : 'desc' };
}
