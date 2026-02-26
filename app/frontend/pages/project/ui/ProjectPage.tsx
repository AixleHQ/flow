import PlayArrowIcon from '@mui/icons-material/PlayArrow';
import { Box, Breadcrumbs, Button, CircularProgress, Grid, Link, Tab, Tabs, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useNavigate, useParams } from '@tanstack/react-router';
import { useMemo } from 'react';

import { AgentsPanel } from 'features/agents-management';
import { AssetsPanel } from 'features/assets-management';
import { ConfigItemsPanel } from 'features/config-items-management';
import { McpServersPanel } from 'features/mcp-servers-management';
import { RepositoriesPanel } from 'features/repositories-management';
import { SkillsPanel } from 'features/skills-management';
import { ToolsPanel } from 'features/tools-management';
import { WorkflowsPanel } from 'features/workflows';
import { Routes } from 'shared/routes';
import { SessionHistoryWidget } from 'widgets/session-history';
import { WorkflowRunsWidget } from 'widgets/workflow-runs';

import { useProjectQuery, useProjectTasksQuery } from '../api/projectApi';
import type { ProjectTab } from '../lib/types';

import MembersTab from './MembersTab';
import SettingsTab from './SettingsTab';

const styles = {
  root: {
    minHeight: '100vh',
    backgroundColor: 'background.default',
  },
  header: {
    padding: '24px 32px',
    borderBottom: '1px solid',
    borderColor: 'divider',
    backgroundColor: 'background.paper',
  },
  breadcrumbs: {
    marginBottom: '16px',
  },
  breadcrumbLink: {
    color: 'text.secondary',
    textDecoration: 'none',
    cursor: 'pointer',
    '&:hover': {
      color: 'text.primary',
    },
  },
  titleRow: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  title: {
    fontSize: '28px',
    fontWeight: 600,
    color: 'text.primary',
  },
  tabsContainer: {
    borderBottom: '1px solid',
    borderColor: 'divider',
    backgroundColor: 'background.paper',
  },
  tabs: {
    paddingX: '32px',
  },
  tab: {
    textTransform: 'none',
    fontSize: '14px',
    fontWeight: 500,
    minHeight: '48px',
  },
  content: {
    padding: '32px',
  },
  sectionTitle: {
    fontSize: '18px',
    fontWeight: 600,
    color: 'text.primary',
    marginBottom: '16px',
  },
  taskColumn: {
    backgroundColor: 'background.paper',
    borderRadius: '8px',
    padding: '16px',
    minHeight: '400px',
  },
  taskColumnTitle: {
    fontSize: '12px',
    fontWeight: 600,
    color: 'text.secondary',
    textTransform: 'uppercase',
    marginBottom: '12px',
  },
  taskCard: {
    padding: '12px',
    backgroundColor: 'background.elevated',
    borderRadius: '6px',
    marginBottom: '8px',
    cursor: 'pointer',
    '&:hover': {
      backgroundColor: 'action.hover',
    },
  },
  taskTitle: {
    fontSize: '14px',
    color: 'text.primary',
    marginBottom: '4px',
  },
  taskAssignee: {
    fontSize: '12px',
    color: 'text.secondary',
  },
  empty: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    padding: '48px',
    gap: '12px',
  },
  emptyText: {
    fontSize: '14px',
    color: 'text.secondary',
  },
  loading: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: '400px',
  },
} satisfies Record<string, SxProps<Theme>>;

const VALID_TABS: ProjectTab[] = [
  'assets',
  'repositories',
  'workflows',
  'runs',
  'tasks',
  'sessions',
  'config',
  'agents',
  'tools',
  'mcp-servers',
  'skills',
  'members',
  'settings',
];

const ProjectPage = () => {
  const navigate = useNavigate();
  const params = useParams({ strict: false });
  const projectId = (params as { projectId?: string }).projectId || '';
  const tabParam = (params as { tab?: string }).tab || 'assets';
  const activeTab = useMemo<ProjectTab>(
    () => (VALID_TABS.includes(tabParam as ProjectTab) ? (tabParam as ProjectTab) : 'assets'),
    [tabParam],
  );

  const { data: projectData, isLoading: isLoadingProject } = useProjectQuery(projectId);
  const { data: tasksData } = useProjectTasksQuery(projectId);

  const project = projectData?.data;
  const tasks = tasksData?.items ?? [];

  const handleTabChange = (_: React.SyntheticEvent, newValue: ProjectTab) => {
    navigate({ to: Routes.frontend.companyProjectTabPath(projectId, newValue) });
  };

  if (isLoadingProject) {
    return (
      <Box sx={styles.root}>
        <Box sx={styles.loading}>
          <CircularProgress />
        </Box>
      </Box>
    );
  }

  const renderTasksTab = () => {
    const columns = [
      { key: 'backlog', title: 'Backlog' },
      { key: 'todo', title: 'To Do' },
      { key: 'in_progress', title: 'In Progress' },
      { key: 'done', title: 'Done' },
    ];

    return (
      <Box>
        <Typography sx={styles.sectionTitle}>Tasks from Linear</Typography>
        <Grid container spacing={2}>
          {columns.map((column) => (
            <Grid item xs={12} sm={6} md={3} key={column.key}>
              <Box sx={styles.taskColumn}>
                <Typography sx={styles.taskColumnTitle}>
                  {column.title} ({tasks.filter((t) => t.status === column.key).length})
                </Typography>
                {tasks
                  .filter((t) => t.status === column.key)
                  .map((task) => (
                    <Box key={task.id} sx={styles.taskCard}>
                      <Typography sx={styles.taskTitle}>{task.title}</Typography>
                      {task.assigneeName && <Typography sx={styles.taskAssignee}>{task.assigneeName}</Typography>}
                    </Box>
                  ))}
              </Box>
            </Grid>
          ))}
        </Grid>
      </Box>
    );
  };

  const renderSettingsTab = () => <SettingsTab projectId={projectId} />;

  return (
    <Box sx={styles.root}>
      {/* Header */}
      <Box sx={styles.header}>
        <Breadcrumbs sx={styles.breadcrumbs}>
          <Link sx={styles.breadcrumbLink} onClick={() => navigate({ to: Routes.frontend.companyProjectsPath })}>
            Projects
          </Link>
          <Typography color="text.primary">{project?.name}</Typography>
        </Breadcrumbs>
        <Box sx={styles.titleRow}>
          <Typography sx={styles.title}>{project?.name}</Typography>
          <Button
            variant="contained"
            startIcon={<PlayArrowIcon />}
            onClick={() => navigate({ to: Routes.frontend.companyProjectTabPath(projectId, 'workflows') })}
          >
            Run Workflow
          </Button>
        </Box>
      </Box>

      {/* Tabs */}
      <Box sx={styles.tabsContainer}>
        <Tabs value={activeTab} onChange={handleTabChange} sx={styles.tabs} variant="scrollable" scrollButtons="auto">
          <Tab value="assets" label="Assets" sx={styles.tab} />
          <Tab value="repositories" label="Repositories" sx={styles.tab} />
          <Tab value="workflows" label="Workflows" sx={styles.tab} />
          <Tab value="runs" label="Runs" sx={styles.tab} />
          <Tab value="tasks" label="Tasks" sx={styles.tab} />
          <Tab value="sessions" label="Sessions" sx={styles.tab} />
          <Tab value="config" label="Secrets & Variables" sx={styles.tab} />
          <Tab value="agents" label="Agents" sx={styles.tab} />
          <Tab value="tools" label="Tools" sx={styles.tab} />
          <Tab value="mcp-servers" label="MCP Servers" sx={styles.tab} />
          <Tab value="skills" label="Skills" sx={styles.tab} />
          <Tab value="members" label="Members" sx={styles.tab} />
          <Tab value="settings" label="Settings" sx={styles.tab} />
        </Tabs>
      </Box>

      {/* Content */}
      <Box sx={styles.content}>
        {activeTab === 'workflows' && <WorkflowsPanel projectId={Number(projectId)} />}
        {activeTab === 'runs' && (
          <Box sx={{ px: 2, py: 2 }}>
            <WorkflowRunsWidget
              projectId={Number(projectId)}
              onRunSelect={(id) => navigate({ to: Routes.frontend.workflowRunPath(projectId, String(id)) as string })}
            />
          </Box>
        )}
        {activeTab === 'assets' && <AssetsPanel projectId={Number(projectId)} />}
        {activeTab === 'tasks' && renderTasksTab()}
        {activeTab === 'sessions' && (
          <Box>
            <Box sx={{ px: 2, pt: 2, display: 'flex', justifyContent: 'flex-end' }}>
              <Button
                variant="contained"
                size="small"
                onClick={() =>
                  navigate({
                    to: Routes.frontend.companyProjectSessionNewPath(projectId) as string,
                  })
                }
              >
                New Session
              </Button>
            </Box>
            <Box sx={{ px: 2, py: 2 }}>
              <SessionHistoryWidget
                projectId={Number(projectId)}
                onSessionSelect={(id) =>
                  navigate({ to: Routes.frontend.companyProjectSessionPath(projectId, String(id)) as string })
                }
              />
            </Box>
          </Box>
        )}
        {activeTab === 'members' && <MembersTab projectId={Number(projectId)} ownerId={project?.ownerId ?? 0} />}
        {activeTab === 'config' && <ConfigItemsPanel projectId={Number(projectId)} />}
        {activeTab === 'agents' && <AgentsPanel projectId={Number(projectId)} />}
        {activeTab === 'tools' && <ToolsPanel projectId={Number(projectId)} />}
        {activeTab === 'mcp-servers' && <McpServersPanel projectId={Number(projectId)} />}
        {activeTab === 'skills' && <SkillsPanel projectId={Number(projectId)} />}
        {activeTab === 'repositories' && <RepositoriesPanel projectId={Number(projectId)} />}
        {activeTab === 'settings' && renderSettingsTab()}
      </Box>
    </Box>
  );
};

export default ProjectPage;
