import type { Task } from './types';

export function normalizeTask(t: Task): Task {
  return {
    ...t,
    title: t.title ?? '',
    tags: t.tags ?? [],
    archived: t.archived ?? false,
    pendingGates: t.pendingGates ?? [],
    ciGates: t.ciGates ?? [],
    recentWorkflowRuns: t.recentWorkflowRuns ?? [],
    assetsCount: t.assetsCount ?? 0,
    childrenCount: t.childrenCount ?? 0,
    commentsCount: t.commentsCount ?? 0,
  };
}
