import { useEffect, useState } from 'react';

import { apiFetch } from 'shared/lib/apiFetch';
import { statusesCompanyProjectTrackerPath } from 'shared/routes';

// The statuses of one tracker's board — its columns — for the pickers.
export function useTrackerStatuses(projectId: number, trackerId: string | number | null): string[] {
  const [statuses, setStatuses] = useState<string[]>([]);
  useEffect(() => {
    let cancelled = false;
    if (!trackerId) {
      setStatuses([]);
      return undefined;
    }
    apiFetch(statusesCompanyProjectTrackerPath(projectId, Number(trackerId)))
      .then((res) => (res.ok ? res.json() : { statuses: [] }))
      .then((data: { statuses?: { name: string }[] }) => {
        if (!cancelled) setStatuses((data.statuses ?? []).map((s) => s.name));
      })
      .catch(() => {
        if (!cancelled) setStatuses([]);
      });
    return () => {
      cancelled = true;
    };
  }, [projectId, trackerId]);
  return statuses;
}
