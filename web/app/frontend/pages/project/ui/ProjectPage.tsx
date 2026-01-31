import { Box, Breadcrumbs, Button, Chip, CircularProgress, Grid, Link, Tab, Tabs, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useNavigate } from '@tanstack/react-router';
import { useState } from 'react';

import { ArtifactCard, type IArtifact } from 'entities/artifact';
import type { IProject } from 'entities/project';
import { RunWorkflowModal } from 'features/run-workflow';
import { useParams } from 'shared/lib/hooks';
import { Routes } from 'shared/routes';

import {
  useProjectQuery,
  useProjectWorkflowsQuery,
  useProjectWorkflowRunsQuery,
  useProjectArtifactsQuery,
  useProjectTasksQuery,
} from '../api/projectApi';
import type { ProjectTab, IWorkflow, IWorkflowRun, ITask } from '../lib/types';

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
  workflowCard: {
    padding: '16px',
    backgroundColor: 'background.paper',
    border: '1px solid',
    borderColor: 'divider',
    borderRadius: '8px',
    cursor: 'pointer',
    transition: 'all 0.2s ease',
    '&:hover': {
      borderColor: 'primary.main',
      backgroundColor: 'background.elevated',
    },
  },
  workflowName: {
    fontSize: '16px',
    fontWeight: 500,
    color: 'text.primary',
    marginBottom: '4px',
  },
  workflowMeta: {
    fontSize: '12px',
    color: 'text.secondary',
  },
  runCard: {
    padding: '12px 16px',
    backgroundColor: 'background.paper',
    border: '1px solid',
    borderColor: 'divider',
    borderRadius: '8px',
    display: 'flex',
    alignItems: 'center',
    gap: '12px',
    cursor: 'pointer',
    transition: 'all 0.2s ease',
    '&:hover': {
      borderColor: 'primary.main',
    },
  },
  runStatus: {
    width: '8px',
    height: '8px',
    borderRadius: '50%',
  },
  runInfo: {
    flex: 1,
  },
  runName: {
    fontSize: '14px',
    fontWeight: 500,
    color: 'text.primary',
  },
  runMeta: {
    fontSize: '12px',
    color: 'text.secondary',
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

// Mock data
const mockProject: IProject = {
  id: '1',
  name: 'Palad Platform',
  description: 'AI coding agents orchestration platform',
  companyId: '1',
  artifactsCount: 42,
  tasksCount: 15,
  activeTasksCount: 3,
  workflowsCount: 8,
  lastActivityAt: new Date().toISOString(),
  createdAt: new Date().toISOString(),
  updatedAt: new Date().toISOString(),
};

const mockWorkflows: IWorkflow[] = [
  {
    id: '1',
    name: 'Create PRD',
    description: 'Generate a Product Requirements Document',
    stepsCount: 5,
    lastRunAt: new Date().toISOString(),
    lastRunStatus: 'completed',
    parameters: [
      { name: 'product_name', type: 'string', description: 'Name of the product', required: true },
      { name: 'target_audience', type: 'string', description: 'Target audience description', required: false },
      {
        name: 'include_mockups',
        type: 'boolean',
        description: 'Include mockup designs',
        defaultValue: false,
        required: false,
      },
    ],
  },
  {
    id: '2',
    name: 'Design UX',
    description: 'Create UX design specification and mockups',
    stepsCount: 8,
    lastRunAt: new Date().toISOString(),
    lastRunStatus: 'running',
    parameters: [
      { name: 'project_type', type: 'string', description: 'Type of project (web, mobile, desktop)', required: true },
      { name: 'complexity', type: 'number', description: 'Complexity level (1-10)', defaultValue: 5, required: false },
    ],
  },
  { id: '3', name: 'Implement Feature', stepsCount: 12 },
];

const mockWorkflowRuns: IWorkflowRun[] = [
  {
    id: '1',
    workflowId: '2',
    workflowName: 'Design UX',
    status: 'running',
    startedAt: new Date(Date.now() - 30 * 60 * 1000).toISOString(),
    userId: '1',
    userName: 'Artem',
    currentStep: 4,
    totalSteps: 8,
    totalCost: 2.45,
  },
  {
    id: '2',
    workflowId: '1',
    workflowName: 'Create PRD',
    status: 'completed',
    startedAt: new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString(),
    completedAt: new Date(Date.now() - 1 * 60 * 60 * 1000).toISOString(),
    userId: '1',
    userName: 'Artem',
    currentStep: 5,
    totalSteps: 5,
    totalCost: 5.12,
  },
];

const mockArtifacts: IArtifact[] = [
  {
    id: '1',
    name: 'prd.md',
    type: 'document',
    workflowName: 'Create PRD',
    stepName: 'Generate PRD',
    userName: 'Artem',
    createdAt: new Date().toISOString(),
  },
  {
    id: '2',
    name: 'ux-design-specification.md',
    type: 'document',
    workflowName: 'Design UX',
    stepName: 'UX Spec',
    userName: 'Artem',
    createdAt: new Date().toISOString(),
  },
  {
    id: '3',
    name: 'mockups.html',
    type: 'code',
    workflowName: 'Design UX',
    stepName: 'Mockups',
    userName: 'Artem',
    createdAt: new Date().toISOString(),
  },
];

const mockTasks: ITask[] = [
  { id: '1', title: 'Setup project structure', status: 'done', assigneeName: 'Artem' },
  { id: '2', title: 'Create PRD document', status: 'done', assigneeName: 'Artem' },
  { id: '3', title: 'Design UX specification', status: 'in_progress', assigneeName: 'Artem' },
  { id: '4', title: 'Implement frontend components', status: 'todo', assigneeName: 'Artem' },
  { id: '5', title: 'Setup CI/CD pipeline', status: 'backlog' },
];

const getStatusColor = (status: string): string => {
  switch (status) {
    case 'completed':
    case 'done':
      return '#22C55E';
    case 'running':
    case 'in_progress':
      return '#3B82F6';
    case 'error':
      return '#EF4444';
    default:
      return '#666666';
  }
};

const ProjectPage = () => {
  const navigate = useNavigate();
  const { projectId } = useParams({ from: Routes.frontend.companyProjectPath('$projectId') });
  const [activeTab, setActiveTab] = useState<ProjectTab>('overview');
  const [runWorkflowModalOpen, setRunWorkflowModalOpen] = useState(false);
  const [selectedWorkflow, setSelectedWorkflow] = useState<IWorkflow | null>(null);

  const { data: projectData, isLoading: isLoadingProject } = useProjectQuery(projectId);
  const { data: workflowsData } = useProjectWorkflowsQuery(projectId);
  const { data: runsData } = useProjectWorkflowRunsQuery(projectId);
  const { data: artifactsData } = useProjectArtifactsQuery(projectId);
  const { data: tasksData } = useProjectTasksQuery(projectId);

  // Use mock data if API returns empty
  const project = projectData?.data || mockProject;
  const workflows = workflowsData?.data?.length ? workflowsData.data : mockWorkflows;
  const runs = runsData?.data?.length ? runsData.data : mockWorkflowRuns;
  const artifacts = artifactsData?.data?.length ? artifactsData.data : mockArtifacts;
  const tasks = tasksData?.data?.length ? tasksData.data : mockTasks;

  const handleTabChange = (_: React.SyntheticEvent, newValue: ProjectTab) => {
    setActiveTab(newValue);
  };

  const handleWorkflowRunClick = (runId: string) => {
    navigate({ to: '/projects/$projectId/workflow-runs/$runId', params: { projectId, runId } });
  };

  const handleWorkflowClick = (workflow: IWorkflow) => {
    setSelectedWorkflow(workflow);
    setRunWorkflowModalOpen(true);
  };

  const handleRunWorkflow = (params: Record<string, string | number | boolean>) => {
    // In real app, this would trigger the workflow run
    console.log('Running workflow:', selectedWorkflow?.id, 'with params:', params);
    navigate({
      to: '/projects/$projectId/workflow-runs/$runId',
      params: { projectId, runId: 'new-run-id' },
    });
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

  const renderOverviewTab = () => (
    <Box>
      {/* Active Runs */}
      {runs.filter((r) => r.status === 'running').length > 0 && (
        <Box sx={{ marginBottom: '32px' }}>
          <Typography sx={styles.sectionTitle}>Active Runs</Typography>
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
            {runs
              .filter((r) => r.status === 'running')
              .map((run) => (
                <Box key={run.id} sx={styles.runCard} onClick={() => handleWorkflowRunClick(run.id)}>
                  <Box sx={{ ...styles.runStatus, backgroundColor: getStatusColor(run.status) }} />
                  <Box sx={styles.runInfo}>
                    <Typography sx={styles.runName}>{run.workflowName}</Typography>
                    <Typography sx={styles.runMeta}>
                      Step {run.currentStep}/{run.totalSteps} • {run.userName}
                    </Typography>
                  </Box>
                  {run.totalCost !== undefined && (
                    <Typography
                      sx={{ color: 'success.main', fontFamily: '"JetBrains Mono", monospace', fontSize: '14px' }}
                    >
                      ${run.totalCost.toFixed(2)}
                    </Typography>
                  )}
                </Box>
              ))}
          </Box>
        </Box>
      )}

      {/* Workflows */}
      <Box sx={{ marginBottom: '32px' }}>
        <Typography sx={styles.sectionTitle}>Workflows</Typography>
        <Grid container spacing={2}>
          {workflows.map((workflow) => (
            <Grid item xs={12} sm={6} md={4} key={workflow.id}>
              <Box sx={styles.workflowCard} onClick={() => handleWorkflowClick(workflow)}>
                <Typography sx={styles.workflowName}>{workflow.name}</Typography>
                <Typography sx={styles.workflowMeta}>
                  {workflow.stepsCount} steps
                  {workflow.lastRunStatus && (
                    <>
                      {' '}
                      • <span style={{ color: getStatusColor(workflow.lastRunStatus) }}>{workflow.lastRunStatus}</span>
                    </>
                  )}
                </Typography>
              </Box>
            </Grid>
          ))}
        </Grid>
      </Box>

      {/* Recent Artifacts */}
      <Box>
        <Typography sx={styles.sectionTitle}>Recent Artifacts</Typography>
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
          {artifacts.slice(0, 5).map((artifact) => (
            <ArtifactCard key={artifact.id} artifact={artifact} />
          ))}
        </Box>
      </Box>
    </Box>
  );

  const renderWorkflowsTab = () => (
    <Box>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '24px' }}>
        <Typography sx={styles.sectionTitle}>All Workflows</Typography>
        <Button variant="contained" onClick={() => navigate({ to: '/workflow-builder/new' })}>
          Create Workflow
        </Button>
      </Box>
      <Grid container spacing={2}>
        {workflows.map((workflow) => (
          <Grid item xs={12} sm={6} md={4} key={workflow.id}>
            <Box sx={styles.workflowCard} onClick={() => handleWorkflowClick(workflow)}>
              <Typography sx={styles.workflowName}>{workflow.name}</Typography>
              <Typography sx={styles.workflowMeta}>{workflow.stepsCount} steps</Typography>
            </Box>
          </Grid>
        ))}
      </Grid>
    </Box>
  );

  const renderArtifactsTab = () => (
    <Box>
      <Typography sx={styles.sectionTitle}>All Artifacts ({artifacts.length})</Typography>
      <Box sx={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
        {artifacts.map((artifact) => (
          <ArtifactCard key={artifact.id} artifact={artifact} />
        ))}
      </Box>
    </Box>
  );

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
          <Link sx={styles.breadcrumbLink} onClick={() => navigate({ to: '/projects' })}>
            Projects
          </Link>
          <Typography color="text.primary">{project.name}</Typography>
        </Breadcrumbs>
        <Box sx={styles.titleRow}>
          <Typography sx={styles.title}>{project.name}</Typography>
          <Button variant="contained">Run Workflow</Button>
        </Box>
      </Box>

      {/* Tabs */}
      <Box sx={styles.tabsContainer}>
        <Tabs value={activeTab} onChange={handleTabChange} sx={styles.tabs}>
          <Tab value="overview" label="Overview" sx={styles.tab} />
          <Tab
            value="workflows"
            label={
              <Box sx={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                Workflows
                <Chip label={workflows.length} size="small" />
              </Box>
            }
            sx={styles.tab}
          />
          <Tab
            value="artifacts"
            label={
              <Box sx={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                Artifacts
                <Chip label={artifacts.length} size="small" />
              </Box>
            }
            sx={styles.tab}
          />
          <Tab
            value="tasks"
            label={
              <Box sx={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                Tasks
                <Chip label={tasks.length} size="small" />
              </Box>
            }
            sx={styles.tab}
          />
          <Tab value="settings" label="Settings" sx={styles.tab} />
        </Tabs>
      </Box>

      {/* Content */}
      <Box sx={styles.content}>
        {activeTab === 'overview' && renderOverviewTab()}
        {activeTab === 'workflows' && renderWorkflowsTab()}
        {activeTab === 'artifacts' && renderArtifactsTab()}
        {activeTab === 'tasks' && renderTasksTab()}
        {activeTab === 'settings' && renderSettingsTab()}
      </Box>

      {/* Run Workflow Modal */}
      <RunWorkflowModal
        open={runWorkflowModalOpen}
        workflow={selectedWorkflow}
        onClose={() => {
          setRunWorkflowModalOpen(false);
          setSelectedWorkflow(null);
        }}
        onRun={handleRunWorkflow}
      />
    </Box>
  );
};

export default ProjectPage;
