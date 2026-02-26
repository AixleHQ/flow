import {
  Box,
  Card,
  CardContent,
  Chip,
  Collapse,
  IconButton,
  List,
  ListItem,
  ListItemText,
  Stack,
  Typography,
} from '@mui/material';
import DeleteIcon from '@mui/icons-material/Delete';
import ExpandLessIcon from '@mui/icons-material/ExpandLess';
import ExpandMoreIcon from '@mui/icons-material/ExpandMore';
import { type FC, useState } from 'react';

import type { Step } from '../lib/types';

interface StepCardProps {
  step: Step;
  allSteps?: Step[];
  onDelete: (id: number) => void;
  onEdit: (step: Step) => void;
}

const StepCard: FC<StepCardProps> = ({ step, allSteps = [], onDelete, onEdit }) => {
  const [expanded, setExpanded] = useState(false);

  return (
    <Card variant="outlined" sx={{ mb: 1 }}>
      <CardContent sx={{ py: 1.5, '&:last-child': { pb: 1.5 } }}>
        <Stack direction="row" alignItems="center" justifyContent="space-between">
          <Stack direction="row" alignItems="center" spacing={1} sx={{ cursor: 'pointer', flex: 1 }} onClick={() => onEdit(step)}>
            <Typography variant="body2" color="text.secondary" sx={{ minWidth: 24 }}>
              {step.position}.
            </Typography>
            <Typography variant="subtitle2">{step.name}</Typography>
            {step.allowNonInteractive && <Chip label="Auto-run" size="small" color="info" />}
            {step.agentId && <Chip label="Agent" size="small" variant="outlined" />}
            {(step.dependsOnStepIds ?? []).length === 0 && (
              <Chip label="Root" size="small" variant="outlined" color="default" />
            )}
            {(step.dependsOnStepIds ?? []).length > 0 && (
              <Chip
                label={`after: ${(step.dependsOnStepIds ?? [])
                  .map((id) => allSteps.find((s) => s.id === id)?.name ?? `#${id}`)
                  .join(', ')}`}
                size="small"
                variant="outlined"
                color="secondary"
              />
            )}
          </Stack>
          <Stack direction="row" spacing={0.5}>
            <IconButton size="small" onClick={() => setExpanded(!expanded)}>
              {expanded ? <ExpandLessIcon fontSize="small" /> : <ExpandMoreIcon fontSize="small" />}
            </IconButton>
            <IconButton size="small" onClick={() => onDelete(step.id)} color="error">
              <DeleteIcon fontSize="small" />
            </IconButton>
          </Stack>
        </Stack>

        <Collapse in={expanded}>
          <Box sx={{ mt: 1.5, pl: 4 }}>
            {step.description && (
              <Typography variant="body2" color="text.secondary" sx={{ mb: 1 }}>
                {step.description}
              </Typography>
            )}
            {step.instructions && (
              <Typography
                variant="body2"
                sx={{ fontFamily: '"JetBrains Mono", monospace', fontSize: '0.8rem', whiteSpace: 'pre-wrap', mb: 1 }}
              >
                {step.instructions}
              </Typography>
            )}
            {step.subSteps.length > 0 && (
              <>
                <Typography variant="caption" color="text.secondary">
                  Sub-steps ({step.subSteps.length})
                </Typography>
                <List dense disablePadding>
                  {step.subSteps.map((ss) => (
                    <ListItem key={ss.id} disableGutters sx={{ py: 0 }}>
                      <ListItemText
                        primary={`${ss.position}. ${ss.name}`}
                        secondary={ss.description}
                        primaryTypographyProps={{ variant: 'body2' }}
                      />
                      {!ss.required && <Chip label="Optional" size="small" variant="outlined" />}
                    </ListItem>
                  ))}
                </List>
              </>
            )}
          </Box>
        </Collapse>
      </CardContent>
    </Card>
  );
};

export { StepCard };
