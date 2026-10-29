import { Head, Link, usePage } from '@inertiajs/react';
import { Alert, Anchor, Box, Stack, Text } from '@mantine/core';

import type { Project, Runner } from '@/types/generated';

import { useFeatureFlag } from 'shared/lib/hooks/useFeatureFlag';
import { useProjectPermissions } from 'shared/lib/hooks/useProjectPermissions';
import type { RunnerTypeOption } from 'shared/resources/runners/runnerConfig';
import { RunnerDetails, type RunnerWorkflowUse } from 'shared/resources/runners/RunnerDetails';
import { projectRunnerPaths } from 'shared/resources/runners/runnerPaths';
import { companySettingsRunnerPath } from 'shared/routes';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface PageProps {
  project: Pick<Project, 'id' | 'name'>;
  runner: Runner;
  runnerTypes: RunnerTypeOption[];
  /** False for a company runner, which is managed from company settings only. */
  canManage: boolean;
  workflowsUsing?: RunnerWorkflowUse[];
  [key: string]: unknown;
}

const RunnerPage = () => {
  const { project, runner, runnerTypes, canManage, workflowsUsing } = usePage<PageProps>().props;
  const { canManageCompany } = useProjectPermissions();
  const externalRunners = useFeatureFlag('externalRunners');

  if (!externalRunners) return null;

  return (
    <Box>
      <Head title={`${runner.name} — Runners — ${project.name}`} />
      <Stack gap="lg">
        {runner.scope === 'company' && (
          <Alert variant="light" color="blue">
            <Text fz="sm">
              A company runner: every project of the company can use it, and it is managed in company settings.{' '}
              {canManageCompany && (
                <Anchor component={Link} href={companySettingsRunnerPath(runner.id)} fz="sm">
                  Manage it there
                </Anchor>
              )}
            </Text>
          </Alert>
        )}
        <RunnerDetails
          runner={runner}
          runnerTypes={runnerTypes}
          canManage={canManage}
          workflowsUsing={workflowsUsing}
          paths={projectRunnerPaths(project.id)}
          backLabel="Runners"
        />
      </Stack>
    </Box>
  );
};

setPageLayout(RunnerPage, persistentProjectLayout);

export default RunnerPage;
