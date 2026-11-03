import { useEffect, useState } from 'react';

import type { DayRange } from './aggregate';
import type { WaitHour } from './types';

export type DayHoursState = { status: 'loading' } | { status: 'failed' } | { status: 'ready'; hours: WaitHour[] };

interface Request {
  companyId: number;
  range: DayRange;
  timeZone: string;
}

/** One opened day's hours of a company's breakdown, fetched when the day is first opened and kept while the dialog is. */
export function useDayHours({ companyId, range, timeZone }: Request, day: string | null): DayHoursState | null {
  const [results, setResults] = useState<Record<string, DayHoursState>>({});
  const known = day ? results[day] : undefined;

  useEffect(() => {
    if (!day || known) return;
    const controller = new AbortController();
    const query = new URLSearchParams({ from: range.start, to: range.end, day, time_zone: timeZone });
    fetch(`/admin/dashboard/companies/${companyId}/hours.json?${query}`, {
      headers: { Accept: 'application/json' },
      signal: controller.signal,
    })
      .then((response) => {
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        return response.json() as Promise<{ hours: WaitHour[] }>;
      })
      .then(({ hours }) => setResults((was) => ({ ...was, [day]: { status: 'ready', hours } })))
      .catch(() => {
        if (!controller.signal.aborted) setResults((was) => ({ ...was, [day]: { status: 'failed' } }));
      });
    return () => controller.abort();
  }, [companyId, range.start, range.end, timeZone, day, known]);

  if (!day) return null;
  return known ?? { status: 'loading' };
}
