import { Head, Link, usePage } from '@inertiajs/react';
import { Anchor, Box, Button, Group, Stack, Text, Title } from '@mantine/core';
import { IconPlus, IconServer } from '@tabler/icons-react';
import { useState } from 'react';

import type { Project, Runner } from '@/types/generated';

import { useFeatureFlag } from 'shared/lib/hooks/useFeatureFlag';
import { useProjectPermissions } from 'shared/lib/hooks/useProjectPermissions';
import type { RunnerTypeOption } from 'shared/resources/runners/runnerConfig';
import { RunnerFormModal } from 'shared/resources/runners/RunnerFormModal';
import { projectRunnerPaths } from 'shared/resources/runners/runnerPaths';
import { RunnersTable } from 'shared/resources/runners/RunnersTable';
import { companySettingsRunnersPath } from 'shared/routes';
import { EmptyState } from 'shared/ui';
import { PageHeader } from 'shared/ui/PageHeader';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

interface PageProps {
  project: Pick<Project, 'id' | 'name'>;
  /** The project's own runners and the company's; `scope` tells them apart. */
  runners: Runner[];
  runnerTypes: RunnerTypeOption[];
  /** May create a project runner: a company admin or the project owner. */
  canManage: boolean;
  [key: string]: unknown;
}

const RunnersPage = () => {
  const { project, runners, runnerTypes, canManage } = usePage<PageProps>().props;
  const { canManageCompany } = useProjectPermissions();
  const externalRunners = useFeatureFlag('externalRunners');
  const [creating, setCreating] = useState(false);

  if (!externalRunners) return null;

  const paths = projectRunnerPaths(project.id);
  const companyRunners = runners.filter((runner) => runner.scope === 'company');
  const projectRunners = runners.filter((runner) => runner.scope === 'project');
  const pathFor = (runner: Runner) => paths.runner(runner.id);

  return (
    <Box>
      <Head title={`Runners — ${project.name}`} />
      <PageHeader
        title="Runners"
        subtitle="Machines this project’s agent sessions can run on instead of the hosted runtime."
        actions={
          canManage && (
            <Button leftSection={<IconPlus size={16} />} onClick={() => setCreating(true)}>
              New runner
            </Button>
          )
        }
      />

      <Stack gap="xl">
        <Stack gap="sm" component="section" aria-labelledby="company-runners">
          <Group justify="space-between">
            <Title order={2} fz="md" fw={600} id="company-runners">
              From your company
            </Title>
            {canManageCompany && (
              <Anchor component={Link} href={companySettingsRunnersPath()} fz="sm">
                Manage in company settings
              </Anchor>
            )}
          </Group>
          {companyRunners.length === 0 ? (
            <Text fz="sm" c="dimmed">
              Your company has no runners.
            </Text>
          ) : (
            <RunnersTable runners={companyRunners} pathFor={pathFor} />
          )}
        </Stack>

        <Stack gap="sm" component="section" aria-labelledby="project-runners">
          <Title order={2} fz="md" fw={600} id="project-runners">
            This project
          </Title>
          {projectRunners.length === 0 ? (
            <EmptyState
              icon={<IconServer size={22} />}
              title="No project runners"
              description="A project runner is used only by this project."
            />
          ) : (
            <RunnersTable runners={projectRunners} pathFor={pathFor} />
          )}
        </Stack>
      </Stack>

      {canManage && (
        <RunnerFormModal
          opened={creating}
          onClose={() => setCreating(false)}
          runnerTypes={runnerTypes}
          paths={paths}
        />
      )}
    </Box>
  );
};

setPageLayout(RunnersPage, persistentProjectLayout);

export default RunnersPage;
