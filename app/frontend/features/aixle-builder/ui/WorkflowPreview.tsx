import AccountTreeIcon from '@mui/icons-material/AccountTree';
import ExpandMoreIcon from '@mui/icons-material/ExpandMore';
import { Accordion, AccordionDetails, AccordionSummary, Box, Chip, Typography, type SxProps } from '@mui/material';
import { type FC, useEffect } from 'react';

import { useGetWorkflowQuery } from 'features/workflows';

import type { MetaActivity } from '../lib/useMetaActivityChannel';

const styles = {
  root: { display: 'flex', flexDirection: 'column', height: '100%', overflow: 'hidden' },
  header: {
    px: 2,
    py: 1.5,
    borderBottom: '1px solid',
    borderColor: 'divider',
    display: 'flex',
    alignItems: 'center',
    gap: 1,
  },
  title: { fontSize: 14, fontWeight: 600, color: 'text.primary' },
  content: { flex: 1, overflowY: 'auto', px: 1, py: 1 },
  empty: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    height: '100%',
    color: 'text.disabled',
    fontSize: 13,
  },
  stepName: { fontSize: 13, fontWeight: 500 },
  stepMeta: { fontSize: 12, color: 'text.secondary' },
  subStep: { fontSize: 12, color: 'text.secondary', pl: 2, py: 0.25 },
} satisfies Record<string, SxProps>;

interface WorkflowPreviewProps {
  projectId: number;
  workflowId: number | null;
  activities: MetaActivity[];
}

export const WorkflowPreview: FC<WorkflowPreviewProps> = ({ projectId, workflowId, activities }) => {
  const { data: workflow, refetch } = useGetWorkflowQuery({ projectId, id: workflowId! }, { skip: !workflowId });

  // Refetch when new workflow/step/sub_step activities arrive
  const activityCount = activities.filter((a) =>
    [
      'created_step',
      'created_sub_step',
      'updated_step',
      'deleted_step',
      'reordered_steps',
      'created_workflow',
    ].includes(a.action),
  ).length;

  useEffect(() => {
    if (workflowId && activityCount > 0) {
      refetch();
    }
  }, [activityCount, workflowId, refetch]);

  if (!workflowId || !workflow) {
    return (
      <Box sx={styles.root}>
        <Box sx={styles.header}>
          <AccountTreeIcon sx={{ fontSize: 18 }} />
          <Typography sx={styles.title}>Workflow Preview</Typography>
        </Box>
        <Box sx={styles.empty}>No workflow created yet</Box>
      </Box>
    );
  }

  interface WorkflowStep {
    id: number;
    name: string;
    position: number;
    agent?: { title: string } | null;
    subSteps?: { id: number; name: string; position: number }[];
  }

  const steps: WorkflowStep[] = (workflow as unknown as { steps?: WorkflowStep[] })?.steps || [];

  return (
    <Box sx={styles.root}>
      <Box sx={styles.header}>
        <AccountTreeIcon sx={{ fontSize: 18 }} />
        <Typography sx={styles.title}>{workflow.name}</Typography>
        <Chip label={`${steps.length} steps`} size="small" variant="outlined" />
      </Box>
      <Box sx={styles.content}>
        {steps.map((step) => (
          <Accordion
            key={step.id}
            disableGutters
            elevation={0}
            sx={{
              '&:before': { display: 'none' },
              border: '1px solid',
              borderColor: 'divider',
              mb: 0.5,
              borderRadius: 1,
            }}
          >
            <AccordionSummary
              expandIcon={<ExpandMoreIcon />}
              sx={{ minHeight: 36, '& .MuiAccordionSummary-content': { my: 0.5 } }}
            >
              <Box>
                <Typography sx={styles.stepName}>
                  {step.position}. {step.name}
                </Typography>
                <Typography sx={styles.stepMeta}>
                  {step.agent?.title || 'No agent'} &middot; {step.subSteps?.length || 0} sub-steps
                </Typography>
              </Box>
            </AccordionSummary>
            <AccordionDetails sx={{ pt: 0, pb: 1 }}>
              {step.subSteps?.map((ss) => (
                <Typography key={ss.id} sx={styles.subStep}>
                  {ss.position}. {ss.name}
                </Typography>
              ))}
              {(!step.subSteps || step.subSteps.length === 0) && (
                <Typography sx={{ fontSize: 12, color: 'text.disabled' }}>No sub-steps</Typography>
              )}
            </AccordionDetails>
          </Accordion>
        ))}
      </Box>
    </Box>
  );
};
