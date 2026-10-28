import { Head, usePage } from '@inertiajs/react';

import type { Runner } from '@/types/generated';

import { AuthLayout } from 'layouts/AuthLayout';

import { useFeatureFlag } from 'shared/lib/hooks/useFeatureFlag';
import type { RunnerTypeOption } from 'shared/resources/runners/runnerConfig';
import { RunnerDetails } from 'shared/resources/runners/RunnerDetails';
import { companyRunnerPaths } from 'shared/resources/runners/runnerPaths';
import type { SharedProps } from 'shared/ui';

import { SettingsTabs } from './SettingsTabs';

interface PageProps extends SharedProps {
  runner: Runner;
  runnerTypes: RunnerTypeOption[];
  canManage: boolean;
}

export default function RunnerPage() {
  const { runner, runnerTypes, canManage, currentUser } = usePage<PageProps>().props;
  const externalRunners = useFeatureFlag('externalRunners');

  if (!externalRunners) return <AuthLayout>{null}</AuthLayout>;

  return (
    <AuthLayout>
      <Head title={`${runner.name} — Runners`} />
      <SettingsTabs active="runners" companyName={currentUser?.currentCompany?.name ?? ''}>
        <RunnerDetails
          runner={runner}
          runnerTypes={runnerTypes}
          canManage={canManage}
          paths={companyRunnerPaths()}
          backLabel="All runners"
        />
      </SettingsTabs>
    </AuthLayout>
  );
}
