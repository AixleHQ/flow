import { useEffect, useState } from 'react';

import { apiFetch } from 'shared/lib/apiFetch';
import { statusesCompanyProjectTrackerPath } from 'shared/routes';

export interface TrackerStatuses {
  statuses: string[];
  loading: boolean;
  failed: boolean;
}

const IDLE: TrackerStatuses = { statuses: [], loading: false, failed: false };

// The statuses of one tracker's board — its columns — for the pickers.
export function useTrackerStatuses(projectId: number, trackerId: string | number | null): TrackerStatuses {
  const [result, setResult] = useState<TrackerStatuses>(IDLE);
  useEffect(() => {
    let cancelled = false;
    if (!trackerId) {
      setResult(IDLE);
      return undefined;
    }
    setResult({ statuses: [], loading: true, failed: false });
    apiFetch(statusesCompanyProjectTrackerPath(projectId, Number(trackerId)))
      .then((res) => (res.ok ? res.json() : Promise.reject(new Error(String(res.status)))))
      .then((data: { statuses?: { name: string }[] }) => {
        if (!cancelled)
          setResult({ statuses: (data.statuses ?? []).map((s) => s.name), loading: false, failed: false });
      })
      .catch(() => {
        if (!cancelled) setResult({ statuses: [], loading: false, failed: true });
      });
    return () => {
      cancelled = true;
    };
  }, [projectId, trackerId]);
  return result;
}
