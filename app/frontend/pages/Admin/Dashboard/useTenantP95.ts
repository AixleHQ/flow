import { useEffect, useState } from 'react';

import type { DayRange } from './aggregate';
import type { TenantWait } from './types';

export type P95State = { status: 'loading' } | { status: 'failed' } | { status: 'ready'; p95: Map<number, number> };

const NOTHING: P95State = { status: 'ready', p95: new Map() };

/** Every company's p95 wait over the days, fetched once per range and kept while the page is open. */
export function useTenantP95(range: DayRange | null): P95State {
  const [results, setResults] = useState<Record<string, P95State>>({});
  const start = range?.start;
  const end = range?.end;
  const known = start && end ? results[`${start}:${end}`] : undefined;

  useEffect(() => {
    if (!start || !end || known) return;
    const key = `${start}:${end}`;
    const controller = new AbortController();
    fetch(`/admin/dashboard/waits.json?${new URLSearchParams({ from: start, to: end })}`, {
      headers: { Accept: 'application/json' },
      signal: controller.signal,
    })
      .then((response) => {
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        return response.json() as Promise<TenantWait[]>;
      })
      .then((rows) =>
        setResults((was) => ({
          ...was,
          [key]: { status: 'ready', p95: new Map(rows.map((row) => [row.companyId, row.p95])) },
        })),
      )
      .catch(() => {
        if (!controller.signal.aborted) setResults((was) => ({ ...was, [key]: { status: 'failed' } }));
      });
    return () => controller.abort();
  }, [start, end, known]);

  if (!start || !end) return NOTHING;
  return known ?? { status: 'loading' };
}
