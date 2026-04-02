import AccountTreeIcon from '@mui/icons-material/AccountTree';
import ExpandMoreIcon from '@mui/icons-material/ExpandMore';
import { Accordion, AccordionDetails, AccordionSummary, Box, Chip, Typography, type SxProps } from '@mui/material';
import { type FC } from 'react';

import { useGetProjectWorkflowsQuery } from 'features/workflows';

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
  wfName: { fontSize: 13, fontWeight: 500 },
  wfMeta: { fontSize: 12, color: 'text.secondary' },
} satisfies Record<string, SxProps>;

interface WorkflowsListPreviewProps {
  projectId: number;
}

export const WorkflowsListPreview: FC<WorkflowsListPreviewProps> = ({ projectId }) => {
  const { data: workflows } = useGetProjectWorkflowsQuery(projectId, {
    pollingInterval: 10000,
  });

  if (!workflows || workflows.length === 0) {
    return (
      <Box sx={styles.root}>
        <Box sx={styles.header}>
          <AccountTreeIcon sx={{ fontSize: 18 }} />
          <Typography sx={styles.title}>Project Workflows</Typography>
        </Box>
        <Box sx={styles.empty}>No workflows yet</Box>
      </Box>
    );
  }

  return (
    <Box sx={styles.root}>
      <Box sx={styles.header}>
        <AccountTreeIcon sx={{ fontSize: 18 }} />
        <Typography sx={styles.title}>Project Workflows</Typography>
        <Chip label={workflows.length} size="small" variant="outlined" />
      </Box>
      <Box sx={styles.content}>
        {workflows.map((wf) => (
          <Accordion
            key={wf.id}
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
                <Typography sx={styles.wfName}>{wf.name}</Typography>
                <Typography sx={styles.wfMeta}>
                  {wf.stepsCount} steps
                  {wf.scopeIndicator === 'company' && ' · company'}
                </Typography>
              </Box>
            </AccordionSummary>
            <AccordionDetails sx={{ pt: 0, pb: 1, px: 2 }}>
              {wf.descriptionExcerpt ? (
                <Typography sx={{ fontSize: 12, color: 'text.secondary' }}>{wf.descriptionExcerpt}</Typography>
              ) : (
                <Typography sx={{ fontSize: 12, color: 'text.disabled' }}>No description</Typography>
              )}
            </AccordionDetails>
          </Accordion>
        ))}
      </Box>
    </Box>
  );
};
