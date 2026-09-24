import { useCallback, useEffect, useMemo, useState } from 'react';

import type BoardActivity from 'types/generated/BoardActivity';

import { apiFetch } from 'shared/lib/apiFetch';
import { apiV1ProjectActivitiesPath } from 'shared/routes';

export function useBoardActivitiesLoadMore(projectId: number, initialActivities: BoardActivity[]) {
  const [extraActivities, setExtraActivities] = useState<BoardActivity[]>([]);
  const [loading, setLoading] = useState(false);
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(initialActivities.length >= 20);

  useEffect(() => {
    setExtraActivities([]);
    setPage(1);
    setHasMore(initialActivities.length >= 20);
  }, [initialActivities]);

  const loadMore = useCallback(async () => {
    const nextPage = page + 1;
    setLoading(true);
    try {
      const res = await apiFetch(apiV1ProjectActivitiesPath(projectId) + `?page=${nextPage}&per_page=20`);
      if (res.ok) {
        const data = await res.json();
        const items: BoardActivity[] = data.items ?? data ?? [];
        setExtraActivities((prev) => [...prev, ...items]);
        setHasMore(data.meta ? data.meta.page < data.meta.totalPages : items.length >= 20);
        setPage(nextPage);
      }
    } catch {
      /* ignore */
    }
    setLoading(false);
  }, [projectId, page]);

  const activities = useMemo(() => [...initialActivities, ...extraActivities], [initialActivities, extraActivities]);

  return { activities, loading, loadMore, hasMore };
}
