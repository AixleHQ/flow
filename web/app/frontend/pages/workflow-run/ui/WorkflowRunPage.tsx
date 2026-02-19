import { Box, Breadcrumbs, CircularProgress, IconButton, Link, Tooltip, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useNavigate } from '@tanstack/react-router';
import { useState } from 'react';

import { FileTree } from 'features/file-tree';
import { Routes } from 'shared/routes';
import { StatusBar } from 'shared/ui';

import type { IWorkflowRunDetail } from '../lib/types';

const styles = {
  root: {
    height: '100vh',
    display: 'flex',
    flexDirection: 'column',
    backgroundColor: 'background.default',
  },
  header: {
    padding: '12px 24px',
    borderBottom: '1px solid',
    borderColor: 'divider',
    backgroundColor: 'background.paper',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    flexShrink: 0,
  },
  headerLeft: {
    display: 'flex',
    flexDirection: 'column',
    gap: '4px',
  },
  breadcrumbs: {
    '& .MuiBreadcrumbs-separator': {
      marginX: '8px',
    },
  },
  breadcrumbLink: {
    color: 'text.secondary',
    textDecoration: 'none',
    cursor: 'pointer',
    fontSize: '13px',
    '&:hover': {
      color: 'text.primary',
    },
  },
  title: {
    fontSize: '18px',
    fontWeight: 600,
    color: 'text.primary',
  },
  headerRight: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
  },
  actionButton: {
    padding: '8px',
    color: 'text.secondary',
    border: '1px solid',
    borderColor: 'divider',
    borderRadius: '6px',
    '&:hover': {
      backgroundColor: 'action.hover',
      borderColor: 'border.strong',
    },
  },
  dangerButton: {
    color: 'error.main',
    borderColor: 'error.main',
    '&:hover': {
      backgroundColor: 'rgba(239, 68, 68, 0.1)',
    },
  },
  // Workflow Steps - horizontal at top
  stepsContainer: {
    backgroundColor: 'background.paper',
    borderBottom: '1px solid',
    borderColor: 'divider',
    padding: '16px 24px',
    flexShrink: 0,
  },
  stepsHeader: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: '12px',
  },
  stepsTitle: {
    fontSize: '12px',
    fontWeight: 600,
    color: 'text.secondary',
    textTransform: 'uppercase',
  },
  stepsList: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    overflowX: 'auto',
    overflowY: 'hidden',
    flexWrap: 'nowrap',
    paddingBottom: '8px',
    scrollBehavior: 'smooth',
    '&::-webkit-scrollbar': {
      height: '6px',
    },
    '&::-webkit-scrollbar-track': {
      backgroundColor: 'background.elevated',
      borderRadius: '3px',
    },
    '&::-webkit-scrollbar-thumb': {
      backgroundColor: 'divider',
      borderRadius: '3px',
      '&:hover': {
        backgroundColor: 'text.disabled',
      },
    },
  },
  stepItem: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    padding: '8px 12px',
    backgroundColor: 'background.elevated',
    borderRadius: '6px',
    cursor: 'pointer',
    flexShrink: 0,
    border: '1px solid transparent',
    transition: 'all 0.2s ease',
    '&:hover': {
      borderColor: 'border.strong',
    },
  },
  stepItemActive: {
    borderColor: 'primary.main',
    backgroundColor: 'action.selected',
  },
  stepIndicator: {
    width: '24px',
    height: '24px',
    borderRadius: '50%',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    fontSize: '12px',
    fontWeight: 600,
    flexShrink: 0,
  },
  stepIndicatorCompleted: {
    backgroundColor: 'success.main',
    color: 'white',
  },
  stepIndicatorRunning: {
    backgroundColor: 'primary.main',
    color: 'white',
    animation: 'pulse 2s infinite',
    '@keyframes pulse': {
      '0%, 100%': { opacity: 1 },
      '50%': { opacity: 0.6 },
    },
  },
  stepIndicatorPending: {
    backgroundColor: 'background.paper',
    border: '2px solid',
    borderColor: 'divider',
    color: 'text.disabled',
  },
  stepIndicatorError: {
    backgroundColor: 'error.main',
    color: 'white',
  },
  stepInfo: {
    display: 'flex',
    flexDirection: 'column',
    gap: '2px',
  },
  stepName: {
    fontSize: '13px',
    fontWeight: 500,
    color: 'text.primary',
    whiteSpace: 'nowrap',
  },
  stepMeta: {
    fontSize: '11px',
    color: 'text.secondary',
    fontFamily: '"JetBrains Mono", monospace',
    display: 'flex',
    alignItems: 'center',
    gap: '6px',
  },
  stepCost: {
    color: 'success.main',
  },
  stepConnector: {
    width: '24px',
    height: '2px',
    backgroundColor: 'divider',
    flexShrink: 0,
  },
  stepConnectorCompleted: {
    backgroundColor: 'success.main',
  },
  // Main content area - IDE layout
  main: {
    flex: 1,
    display: 'flex',
    overflow: 'hidden',
  },
  // Explorer sidebar (left)
  explorerSidebar: {
    width: '260px',
    borderRight: '1px solid',
    borderColor: 'divider',
    backgroundColor: 'background.paper',
    display: 'flex',
    flexDirection: 'column',
    overflow: 'hidden',
    flexShrink: 0,
  },
  explorerHeader: {
    padding: '12px 16px',
    borderBottom: '1px solid',
    borderColor: 'divider',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    flexShrink: 0,
  },
  explorerTitle: {
    fontSize: '11px',
    fontWeight: 600,
    color: 'text.secondary',
    textTransform: 'uppercase',
    letterSpacing: '0.5px',
  },
  explorerContent: {
    flex: 1,
    overflow: 'auto',
  },
  // Content area (right side)
  contentArea: {
    flex: 1,
    display: 'flex',
    flexDirection: 'column',
    overflow: 'hidden',
  },
  // Split view container - horizontal (side by side)
  splitContainer: {
    flex: 1,
    display: 'flex',
    flexDirection: 'row',
    overflow: 'hidden',
  },
  // Terminal panel (left)
  terminalPanel: {
    flex: 1,
    minWidth: '300px',
    backgroundColor: '#0D0D0D',
    display: 'flex',
    flexDirection: 'column',
    overflow: 'hidden',
  },
  // File Viewer panel (right)
  fileViewerPanel: {
    width: '45%',
    minWidth: '300px',
    borderLeft: '1px solid',
    borderColor: 'divider',
    backgroundColor: 'background.paper',
    display: 'flex',
    flexDirection: 'column',
    overflow: 'hidden',
  },
  panelHeader: {
    padding: '8px 16px',
    borderBottom: '1px solid',
    borderColor: 'divider',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    flexShrink: 0,
    backgroundColor: 'background.elevated',
  },
  panelTitle: {
    fontSize: '12px',
    fontWeight: 500,
    color: 'text.secondary',
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
  },
  panelTitleIcon: {
    fontSize: '14px',
  },
  panelFileName: {
    color: 'text.primary',
    fontFamily: '"JetBrains Mono", monospace',
  },
  panelContent: {
    flex: 1,
    overflow: 'auto',
  },
  placeholder: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    height: '100%',
    gap: '8px',
  },
  placeholderText: {
    fontSize: '13px',
    color: 'text.secondary',
  },
  placeholderSubtext: {
    fontSize: '11px',
    color: 'text.disabled',
  },
  loading: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    height: '100%',
  },
  // Resizer - vertical
  resizer: {
    width: '4px',
    backgroundColor: 'transparent',
    cursor: 'col-resize',
    transition: 'background-color 0.2s',
    '&:hover': {
      backgroundColor: 'primary.main',
    },
  },
} satisfies Record<string, SxProps<Theme>>;

function useWorkflowRun(): IWorkflowRunDetail | null {
  return null; // TODO: fetch from API using useParams projectId, runId
}

const WorkflowRunPage = () => {
  const navigate = useNavigate();
  // Params available for future use: useParams({ strict: false }) contains projectId, runId
  const [isLoading] = useState(false);
  const [activeStepId, setActiveStepId] = useState<string | null>(null);
  const [showExplorer, setShowExplorer] = useState(true);

  // TODO: fetch from API using useParams runId, projectId
  const workflowRun = useWorkflowRun();

  const formatDuration = (startedAt: string, completedAt?: string): string => {
    const start = new Date(startedAt);
    const end = completedAt ? new Date(completedAt) : new Date();
    const diffMs = end.getTime() - start.getTime();
    const diffMins = Math.floor(diffMs / 60000);
    const diffSecs = Math.floor((diffMs % 60000) / 1000);
    return `${diffMins}m ${diffSecs}s`;
  };

  const getStepIndicatorStyle = (status: string): SxProps<Theme> => {
    switch (status) {
      case 'completed':
        return styles.stepIndicatorCompleted;
      case 'running':
        return styles.stepIndicatorRunning;
      case 'error':
        return styles.stepIndicatorError;
      default:
        return styles.stepIndicatorPending;
    }
  };

  const getStepIcon = (status: string, index: number): string => {
    switch (status) {
      case 'completed':
        return '✓';
      case 'running':
        return '●';
      case 'error':
        return '✗';
      default:
        return String(index + 1);
    }
  };

  const getFileIcon = (type?: string): string => {
    switch (type) {
      case 'markdown':
        return '📝';
      case 'json':
        return '{ }';
      case 'html':
        return '🌐';
      default:
        return '📄';
    }
  };

  if (isLoading) {
    return (
      <Box sx={styles.root}>
        <Box sx={styles.loading}>
          <CircularProgress />
        </Box>
      </Box>
    );
  }

  if (!workflowRun) {
    return (
      <Box sx={styles.root}>
        <Box sx={styles.loading}>
          <Typography sx={{ color: 'text.secondary' }}>Workflow run not found</Typography>
        </Box>
      </Box>
    );
  }

  const currentStep = workflowRun.steps.find((s) => s.status === 'running');
  const selectedStep = activeStepId ? workflowRun.steps.find((s) => s.id === activeStepId) : currentStep;
  const sessionStatus =
    workflowRun.status === 'running' ? 'running' : workflowRun.status === 'completed' ? 'completed' : 'error';

  return (
    <Box sx={styles.root}>
      {/* Header */}
      <Box sx={styles.header}>
        <Box sx={styles.headerLeft}>
          <Breadcrumbs sx={styles.breadcrumbs}>
            <Link sx={styles.breadcrumbLink} onClick={() => navigate({ to: Routes.frontend.companyProjectsPath })}>
              Projects
            </Link>
            <Link
              sx={styles.breadcrumbLink}
              onClick={() => navigate({ to: Routes.frontend.companyProjectPath(workflowRun.projectId) })}
            >
              {workflowRun.projectName}
            </Link>
            <Typography color="text.primary" sx={{ fontSize: '13px' }}>
              {workflowRun.workflowName}
            </Typography>
          </Breadcrumbs>
          <Typography sx={styles.title}>{workflowRun.workflowName}</Typography>
        </Box>
        <Box sx={styles.headerRight}>
          <Tooltip title="Toggle Explorer">
            <IconButton sx={styles.actionButton} onClick={() => setShowExplorer(!showExplorer)}>
              <span style={{ fontSize: '14px' }}>📁</span>
            </IconButton>
          </Tooltip>
          {workflowRun.status === 'running' && (
            <Tooltip title="Stop Workflow">
              <IconButton sx={{ ...styles.actionButton, ...styles.dangerButton }}>
                <span style={{ fontSize: '14px' }}>■</span>
              </IconButton>
            </Tooltip>
          )}
        </Box>
      </Box>

      {/* Workflow Steps - Horizontal */}
      <Box sx={styles.stepsContainer}>
        <Box sx={styles.stepsHeader}>
          <Typography sx={styles.stepsTitle}>Workflow Steps</Typography>
          <Typography sx={{ fontSize: '12px', color: 'text.secondary' }}>
            Step {workflowRun.steps.filter((s) => s.status === 'completed').length + (currentStep ? 1 : 0)}/
            {workflowRun.steps.length}
          </Typography>
        </Box>
        <Box sx={styles.stepsList}>
          {workflowRun.steps.map((step, index) => (
            <Box key={step.id} sx={{ display: 'flex', alignItems: 'center' }}>
              {/* Step Item */}
              <Box
                sx={{
                  ...styles.stepItem,
                  ...(selectedStep?.id === step.id ? styles.stepItemActive : {}),
                }}
                onClick={() => setActiveStepId(step.id)}
              >
                <Box sx={{ ...styles.stepIndicator, ...getStepIndicatorStyle(step.status) }}>
                  {getStepIcon(step.status, index)}
                </Box>
                <Box sx={styles.stepInfo}>
                  <Typography sx={styles.stepName}>{step.name}</Typography>
                  <Box sx={styles.stepMeta}>
                    {step.cost !== undefined && (
                      <Typography component="span" sx={styles.stepCost}>
                        ${step.cost.toFixed(2)}
                      </Typography>
                    )}
                    {step.duration && <Typography component="span">{step.duration}</Typography>}
                    {step.status === 'running' && step.user && <Typography component="span">{step.user}</Typography>}
                  </Box>
                </Box>
              </Box>
              {/* Connector */}
              {index < workflowRun.steps.length - 1 && (
                <Box
                  sx={{
                    ...styles.stepConnector,
                    ...(step.status === 'completed' ? styles.stepConnectorCompleted : {}),
                  }}
                />
              )}
            </Box>
          ))}
        </Box>
      </Box>

      {/* Main Content - IDE Layout */}
      <Box sx={styles.main}>
        {/* Explorer Sidebar (Left) */}
        {showExplorer && (
          <Box sx={styles.explorerSidebar}>
            <Box sx={styles.explorerHeader}>
              <Typography sx={styles.explorerTitle}>Explorer</Typography>
              <IconButton size="small" onClick={() => setShowExplorer(false)} sx={{ padding: '4px' }}>
                <span style={{ fontSize: '10px', color: '#666' }}>✕</span>
              </IconButton>
            </Box>
            <Box sx={styles.explorerContent}>
              <FileTree hideHeader />
            </Box>
          </Box>
        )}

        {/* Content Area (Right) */}
        <Box sx={styles.contentArea}>
          <Box sx={styles.splitContainer}>
            {/* Terminal (Left) */}
            <Box sx={styles.terminalPanel}>
              <Box sx={{ ...styles.panelHeader, backgroundColor: '#1A1A1A' }}>
                <Box sx={styles.panelTitle}>
                  <span style={{ fontSize: '14px' }}>⬛</span>
                  <Typography component="span" sx={{ color: 'text.primary' }}>
                    Terminal
                  </Typography>
                  {selectedStep && (
                    <Typography component="span" sx={{ color: 'text.disabled', fontSize: '11px' }}>
                      — {selectedStep.name}
                    </Typography>
                  )}
                </Box>
              </Box>
              <Box sx={styles.panelContent}>
                <Box sx={styles.placeholder}>
                  <Typography sx={styles.placeholderText}>
                    {selectedStep ? `Terminal for "${selectedStep.name}"` : 'Select a step to view terminal'}
                  </Typography>
                  <Typography sx={styles.placeholderSubtext}>Connect to session terminal via ttyd</Typography>
                </Box>
              </Box>
            </Box>

            {/* File Viewer (Right) - only shown when asset selected */}
            {selectedStep?.assets?.[0] && (
              <>
                {/* Resizer */}
                <Box sx={styles.resizer} />

                <Box sx={styles.fileViewerPanel}>
                  <Box sx={styles.panelHeader}>
                    <Box sx={styles.panelTitle}>
                      <span style={{ fontSize: '14px' }}>{getFileIcon(selectedStep.assets[0].type)}</span>
                      <Typography component="span" sx={styles.panelFileName}>
                        {selectedStep.assets[0].name}
                      </Typography>
                    </Box>
                    {selectedStep.assets.length > 1 && (
                      <Typography sx={{ fontSize: '11px', color: 'text.disabled' }}>
                        +{selectedStep.assets.length - 1} more
                      </Typography>
                    )}
                  </Box>
                  <Box sx={styles.panelContent}>
                    <Box sx={styles.placeholder}>
                      <Typography sx={styles.placeholderText}>Preview: {selectedStep.assets[0].name}</Typography>
                      <Typography sx={styles.placeholderSubtext}>File content would render here</Typography>
                    </Box>
                  </Box>
                </Box>
              </>
            )}
          </Box>

          {/* Status Bar */}
          <StatusBar
            agent={selectedStep?.agent}
            status={sessionStatus}
            cost={workflowRun.totalCost}
            duration={formatDuration(workflowRun.startedAt, workflowRun.completedAt)}
            user={currentStep?.user}
          />
        </Box>
      </Box>
    </Box>
  );
};

export default WorkflowRunPage;
