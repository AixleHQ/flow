import { Head, usePage } from '@inertiajs/react';
import { Button, Group, Stack, Text } from '@mantine/core';
import { IconPlus, IconServer } from '@tabler/icons-react';
import { useState } from 'react';

import type { Runner } from '@/types/generated';
import { AuthLayout } from 'layouts/AuthLayout';

import { useFeatureFlag } from 'shared/lib/hooks/useFeatureFlag';
import type { RunnerTypeOption } from 'shared/resources/runners/runnerConfig';
import { RunnerFormModal } from 'shared/resources/runners/RunnerFormModal';
import { companyRunnerPaths } from 'shared/resources/runners/runnerPaths';
import { RunnersTable } from 'shared/resources/runners/RunnersTable';
import { EmptyState } from 'shared/ui';
import type { SharedProps } from 'shared/ui';

import { SettingsTabs } from './SettingsTabs';

interface PageProps extends SharedProps {
  runners: Runner[];
  runnerTypes: RunnerTypeOption[];
  canManage: boolean;
}

export default function RunnersPage() {
  const { runners, runnerTypes, canManage, currentUser } = usePage<PageProps>().props;
  const externalRunners = useFeatureFlag('externalRunners');
  const [creating, setCreating] = useState(false);
  const paths = companyRunnerPaths();

  if (!externalRunners) return <AuthLayout>{null}</AuthLayout>;

  const newRunner = canManage && (
    <Button leftSection={<IconPlus size={16} />} onClick={() => setCreating(true)}>
      New runner
    </Button>
  );

  return (
    <AuthLayout>
      <Head title="Runners — Company Settings" />
      <SettingsTabs active="runners" companyName={currentUser?.currentCompany?.name ?? ''}>
        <Stack gap="md">
          <Group justify="space-between" align="flex-start">
            <Text fz="sm" c="dimmed" maw={640}>
              Machines your company runs agent sessions on. Every project of the company can use a company runner.
            </Text>
            {runners.length > 0 && newRunner}
          </Group>

          {runners.length === 0 ? (
            <EmptyState
              icon={<IconServer size={22} />}
              title="No runners yet"
              description="Connect a machine of your own and run agent sessions on it instead of the hosted runtime."
              action={newRunner || undefined}
            />
          ) : (
            <RunnersTable runners={runners} pathFor={(runner) => paths.runner(runner.id)} />
          )}
        </Stack>
      </SettingsTabs>

      {canManage && (
        <RunnerFormModal opened={creating} onClose={() => setCreating(false)} runnerTypes={runnerTypes} paths={paths} />
      )}
    </AuthLayout>
  );
}
