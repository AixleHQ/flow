import { Box, CircularProgress, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useNavigate, useParams } from '@tanstack/react-router';
import { useMemo } from 'react';

import { AgentsPanel } from 'features/agents-management';
import { AssetPreview } from 'features/asset-preview';
import { useGetProjectAssetsQuery, AssetsPanel } from 'features/assets-management';
import { BoardPanel } from 'features/board-management';
import { ConfigItemsPanel } from 'features/config-items-management';
import { McpServersPanel } from 'features/mcp-servers-management';
import { RepositoriesPanel } from 'features/repositories-management';
import { RunWorkflowModal } from 'features/run-workflow';
import { SkillsPanel } from 'features/skills-management';
import { ToolsPanel } from 'features/tools-management';
import { useCreateWorkflowRunMutation } from 'features/workflow-execution';
import { useGetStepsQuery } from 'features/workflow-steps';
import { WorkflowsPanel, type RunWorkflowModalSlot } from 'features/workflows';
import { Routes } from 'shared/routes';
import { SessionHistoryWidget } from 'widgets/session-history';
import { WorkflowRunsWidget } from 'widgets/workflow-runs';

import { useProjectQuery } from '../api/projectApi';
import type { ProjectTab } from '../lib/types';

import MembersTab from './MembersTab';
import SettingsTab from './SettingsTab';

const styles = {
  root: {
    minHeight: '100%',
    backgroundColor: 'background.default',
  },
  content: {
    padding: '24px 32px',
  },
  loading: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: '400px',
  },
  emptyPage: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: '400px',
    gap: 2,
  },
  emptyTitle: {
    fontSize: '20px',
    fontWeight: 500,
    color: 'text.primary',
  },
  emptySubtitle: {
    fontSize: '14px',
    color: 'text.secondary',
  },
} satisfies Record<string, SxProps<Theme>>;

const VALID_TABS: ProjectTab[] = [
  'overview',
  'board',
  'assets',
  'repositories',
  'workflows',
  'runs',
  'sessions',
  'config',
  'agents',
  'tools',
  'mcp-servers',
  'skills',
  'members',
  'settings',
  'analytics',
];

const ConnectedRunModal = ({
  slot,
  projectAssets,
}: {
  slot: RunWorkflowModalSlot;
  projectAssets: { id: number; name: string; folder: string | null; deletedAt: string | null }[];
}) => {
  const { data: steps = [] } = useGetStepsQuery(
    { projectId: slot.projectId, workflowId: slot.workflow?.id ?? 0 },
    { skip: !slot.workflow },
  );
  const [createRun, { isLoading }] = useCreateWorkflowRunMutation();

  return (
    <RunWorkflowModal
      {...slot}
      projectAssets={projectAssets}
      steps={steps}
      onCreateRun={(params) => createRun(params).unwrap()}
      isCreating={isLoading}
    />
  );
};

const OverviewPage = () => (
  <Box sx={styles.emptyPage}>
    <Typography sx={styles.emptyTitle}>Project Overview</Typography>
    <Typography sx={styles.emptySubtitle}>Dashboard with project summary and recent activity coming soon.</Typography>
  </Box>
);

const AnalyticsPage = () => (
  <Box sx={styles.emptyPage}>
    <Typography sx={styles.emptyTitle}>Analytics</Typography>
    <Typography sx={styles.emptySubtitle}>Charts and insights about project performance coming soon.</Typography>
  </Box>
);

const ProjectPage = () => {
  const navigate = useNavigate();
  const params = useParams({ strict: false });
  const projectId = (params as { projectId?: string }).projectId || '';
  const tabParam = (params as { tab?: string }).tab || 'overview';
  const activeTab = useMemo<ProjectTab>(
    () => (VALID_TABS.includes(tabParam as ProjectTab) ? (tabParam as ProjectTab) : 'overview'),
    [tabParam],
  );

  const { data: projectData, isLoading: isLoadingProject } = useProjectQuery(projectId);
  const { data: projectAssets = [] } = useGetProjectAssetsQuery(Number(projectId), { skip: !projectId });

  const project = projectData?.data;

  if (isLoadingProject) {
    return (
      <Box sx={styles.root}>
        <Box sx={styles.loading}>
          <CircularProgress />
        </Box>
      </Box>
    );
  }

  return (
    <Box sx={styles.root}>
      <Box sx={styles.content}>
        {activeTab === 'overview' && <OverviewPage />}
        {activeTab === 'board' && <BoardPanel projectId={Number(projectId)} />}
        {activeTab === 'workflows' && (
          <WorkflowsPanel
            projectId={Number(projectId)}
            renderRunModal={(slot) => <ConnectedRunModal slot={slot} projectAssets={projectAssets} />}
          />
        )}
        {activeTab === 'runs' && (
          <WorkflowRunsWidget
            projectId={Number(projectId)}
            onRunSelect={(id) => navigate({ to: Routes.frontend.workflowRunPath(projectId, String(id)) as string })}
          />
        )}
        {activeTab === 'assets' && (
          <AssetsPanel
            projectId={Number(projectId)}
            renderPreview={(data, onClose) => <AssetPreview asset={data} onClose={onClose} />}
          />
        )}
        {activeTab === 'sessions' && (
          <SessionHistoryWidget
            projectId={Number(projectId)}
            onSessionSelect={(id) =>
              navigate({ to: Routes.frontend.companyProjectSessionPath(projectId, String(id)) as string })
            }
          />
        )}
        {activeTab === 'members' && <MembersTab projectId={Number(projectId)} ownerId={project?.ownerId ?? 0} />}
        {activeTab === 'config' && <ConfigItemsPanel projectId={Number(projectId)} />}
        {activeTab === 'agents' && <AgentsPanel projectId={Number(projectId)} />}
        {activeTab === 'tools' && <ToolsPanel projectId={Number(projectId)} />}
        {activeTab === 'mcp-servers' && <McpServersPanel projectId={Number(projectId)} />}
        {activeTab === 'skills' && <SkillsPanel projectId={Number(projectId)} />}
        {activeTab === 'repositories' && <RepositoriesPanel projectId={Number(projectId)} />}
        {activeTab === 'settings' && <SettingsTab projectId={projectId} />}
        {activeTab === 'analytics' && <AnalyticsPage />}
      </Box>
    </Box>
  );
};

export default ProjectPage;
