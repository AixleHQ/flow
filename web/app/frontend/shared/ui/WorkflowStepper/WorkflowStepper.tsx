import { Box, Collapse, IconButton, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useState } from 'react';

type StepStatus = 'completed' | 'running' | 'running_other' | 'pending' | 'error';

interface IWorkflowStep {
  id: string;
  name: string;
  status: StepStatus;
  agent?: string;
  user?: string;
  duration?: string;
  cost?: number;
  artifacts?: Array<{
    id: string;
    name: string;
    type: string;
  }>;
}

interface IWorkflowStepperProps {
  steps: IWorkflowStep[];
  currentStepId?: string;
  onStepClick?: (stepId: string) => void;
}

const styles = {
  root: {
    display: 'flex',
    flexDirection: 'column',
  },
  step: {
    display: 'flex',
    position: 'relative',
  },
  connector: {
    position: 'absolute',
    left: '15px',
    top: '32px',
    bottom: '0',
    width: '2px',
    backgroundColor: 'divider',
  },
  connectorCompleted: {
    backgroundColor: 'success.main',
  },
  indicatorContainer: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    marginRight: '12px',
    zIndex: 1,
  },
  indicator: {
    width: '32px',
    height: '32px',
    borderRadius: '50%',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'background.elevated',
    border: '2px solid',
    borderColor: 'divider',
    transition: 'all 0.2s ease',
  },
  indicatorCompleted: {
    borderColor: 'success.main',
    backgroundColor: 'success.main',
  },
  indicatorRunning: {
    borderColor: 'primary.main',
    animation: 'pulse 2s infinite',
    '@keyframes pulse': {
      '0%, 100%': { boxShadow: '0 0 0 0 rgba(59, 130, 246, 0.4)' },
      '50%': { boxShadow: '0 0 0 8px rgba(59, 130, 246, 0)' },
    },
  },
  indicatorRunningOther: {
    borderColor: 'warning.main',
  },
  indicatorError: {
    borderColor: 'error.main',
    backgroundColor: 'error.main',
  },
  indicatorIcon: {
    fontSize: '14px',
    color: 'text.primary',
  },
  content: {
    flex: 1,
    paddingBottom: '24px',
  },
  header: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    cursor: 'pointer',
    padding: '4px 8px',
    marginLeft: '-8px',
    borderRadius: '6px',
    '&:hover': {
      backgroundColor: 'action.hover',
    },
  },
  headerInfo: {
    display: 'flex',
    alignItems: 'center',
    gap: '12px',
  },
  stepName: {
    fontSize: '14px',
    fontWeight: 500,
    color: 'text.primary',
  },
  stepNamePending: {
    color: 'text.secondary',
  },
  stepMeta: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    fontSize: '12px',
    color: 'text.secondary',
    fontFamily: '"JetBrains Mono", monospace',
  },
  expandButton: {
    padding: '4px',
    color: 'text.secondary',
  },
  details: {
    paddingTop: '12px',
    paddingLeft: '8px',
  },
  detailRow: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    marginBottom: '8px',
  },
  detailLabel: {
    fontSize: '11px',
    color: 'text.disabled',
    textTransform: 'uppercase',
    minWidth: '60px',
  },
  detailValue: {
    fontSize: '12px',
    color: 'text.secondary',
    fontFamily: '"JetBrains Mono", monospace',
  },
  artifactsList: {
    marginTop: '12px',
  },
  artifactsTitle: {
    fontSize: '11px',
    color: 'text.disabled',
    textTransform: 'uppercase',
    marginBottom: '8px',
  },
  artifact: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    padding: '6px 8px',
    backgroundColor: 'background.paper',
    borderRadius: '4px',
    marginBottom: '4px',
    cursor: 'pointer',
    '&:hover': {
      backgroundColor: 'action.hover',
    },
  },
  artifactIcon: {
    fontSize: '14px',
  },
  artifactName: {
    fontSize: '12px',
    color: 'text.primary',
    fontFamily: '"JetBrains Mono", monospace',
  },
} satisfies Record<string, SxProps<Theme>>;

const getStatusIcon = (status: StepStatus): string => {
  switch (status) {
    case 'completed':
      return '✓';
    case 'running':
    case 'running_other':
      return '●';
    case 'error':
      return '✗';
    default:
      return '';
  }
};

const getIndicatorStyles = (status: StepStatus): SxProps<Theme> => {
  switch (status) {
    case 'completed':
      return styles.indicatorCompleted;
    case 'running':
      return styles.indicatorRunning;
    case 'running_other':
      return styles.indicatorRunningOther;
    case 'error':
      return styles.indicatorError;
    default:
      return {};
  }
};

const getArtifactIcon = (type: string): string => {
  if (type.includes('image')) return '🖼️';
  if (type.includes('pdf')) return '📄';
  if (type.includes('json')) return '{}';
  if (type.includes('md') || type.includes('markdown')) return '📝';
  if (type.includes('code') || type.includes('ts') || type.includes('js')) return '💻';
  return '📎';
};

const WorkflowStepper = ({ steps, currentStepId, onStepClick }: IWorkflowStepperProps) => {
  const [expandedSteps, setExpandedSteps] = useState<Set<string>>(new Set([currentStepId || '']));

  const toggleExpand = (stepId: string) => {
    setExpandedSteps((prev) => {
      const next = new Set(prev);
      if (next.has(stepId)) {
        next.delete(stepId);
      } else {
        next.add(stepId);
      }
      return next;
    });
  };

  return (
    <Box sx={styles.root}>
      {steps.map((step, index) => {
        const isLast = index === steps.length - 1;
        const isExpanded = expandedSteps.has(step.id);
        const hasDetails =
          step.agent || step.duration || step.cost !== undefined || (step.artifacts && step.artifacts.length > 0);

        return (
          <Box key={step.id} sx={styles.step}>
            {/* Connector line */}
            {!isLast && (
              <Box
                sx={{
                  ...styles.connector,
                  ...(step.status === 'completed' ? styles.connectorCompleted : {}),
                }}
              />
            )}

            {/* Indicator */}
            <Box sx={styles.indicatorContainer}>
              <Box sx={{ ...styles.indicator, ...getIndicatorStyles(step.status) }}>
                <Typography sx={styles.indicatorIcon}>{getStatusIcon(step.status)}</Typography>
              </Box>
            </Box>

            {/* Content */}
            <Box sx={styles.content}>
              <Box sx={styles.header} onClick={() => hasDetails && toggleExpand(step.id)}>
                <Box sx={styles.headerInfo}>
                  <Typography
                    sx={{
                      ...styles.stepName,
                      ...(step.status === 'pending' ? styles.stepNamePending : {}),
                    }}
                  >
                    {step.name}
                  </Typography>
                  {step.status === 'running_other' && step.user && (
                    <Typography sx={styles.stepMeta}>{step.user} working...</Typography>
                  )}
                </Box>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                  {step.cost !== undefined && (
                    <Typography sx={{ ...styles.stepMeta, color: 'success.main' }}>${step.cost.toFixed(2)}</Typography>
                  )}
                  {step.duration && <Typography sx={styles.stepMeta}>{step.duration}</Typography>}
                  {hasDetails && (
                    <IconButton sx={styles.expandButton} size="small">
                      <span style={{ fontSize: '12px' }}>{isExpanded ? '▼' : '▶'}</span>
                    </IconButton>
                  )}
                </Box>
              </Box>

              {/* Expandable details */}
              <Collapse in={isExpanded}>
                <Box sx={styles.details}>
                  {step.agent && (
                    <Box sx={styles.detailRow}>
                      <Typography sx={styles.detailLabel}>Agent</Typography>
                      <Typography sx={styles.detailValue}>{step.agent}</Typography>
                    </Box>
                  )}

                  {/* Artifacts */}
                  {step.artifacts && step.artifacts.length > 0 && (
                    <Box sx={styles.artifactsList}>
                      <Typography sx={styles.artifactsTitle}>Artifacts ({step.artifacts.length})</Typography>
                      {step.artifacts.map((artifact) => (
                        <Box
                          key={artifact.id}
                          sx={styles.artifact}
                          onClick={(e) => {
                            e.stopPropagation();
                            onStepClick?.(step.id);
                          }}
                        >
                          <span style={{ fontSize: '14px' }}>{getArtifactIcon(artifact.type)}</span>
                          <Typography sx={styles.artifactName}>{artifact.name}</Typography>
                        </Box>
                      ))}
                    </Box>
                  )}
                </Box>
              </Collapse>
            </Box>
          </Box>
        );
      })}
    </Box>
  );
};

export default WorkflowStepper;
