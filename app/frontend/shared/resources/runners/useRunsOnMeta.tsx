import type { ReactNode } from 'react';

import type { RunnerBadge } from '@/types/generated';

import { useFeatureFlag } from 'shared/lib/hooks/useFeatureFlag';

import { RunsOnBadge } from './runnerChoice';

/** The "Runs on" item of a detail header's meta row, or nothing without the flag or a project. */
export function useRunsOnMeta(
  runner: RunnerBadge | null | undefined,
  runnerId: number | null | undefined,
  projectId: number | null | undefined,
): { label: string; value: ReactNode }[] {
  const externalRunners = useFeatureFlag('externalRunners');
  if (!externalRunners || projectId == null) return [];

  return [{ label: 'Runs on', value: <RunsOnBadge runner={runner} runnerId={runnerId} projectId={projectId} /> }];
}
