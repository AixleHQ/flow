import CloseIcon from '@mui/icons-material/Close';
import { Box, Dialog, DialogContent, DialogTitle, IconButton, Typography } from '@mui/material';
import type { FC } from 'react';

import type { AgentType } from 'entities/user';
import { AGENT_COLORS, getAgentInfo } from 'entities/user';
import { AgentAuthTerminal } from 'features/agent-auth';

interface AgentAuthDialogProps {
  open: boolean;
  agentType: AgentType | null;
  onClose: () => void;
  onAuthComplete: (agentType: AgentType) => void;
}

export const AgentAuthDialog: FC<AgentAuthDialogProps> = ({ open, agentType, onClose, onAuthComplete }) => {
  if (!agentType) return null;

  const info = getAgentInfo(agentType);

  return (
    <Dialog
      open={open}
      onClose={onClose}
      maxWidth="lg"
      fullWidth
      PaperProps={{
        sx: {
          height: '80vh',
          maxHeight: '800px',
          backgroundColor: 'background.paper',
        },
      }}
    >
      <DialogTitle sx={{ display: 'flex', alignItems: 'center', gap: 1.5, pr: 6 }}>
        <Box
          sx={{
            width: 4,
            height: 24,
            borderRadius: 1,
            backgroundColor: AGENT_COLORS[agentType],
            flexShrink: 0,
          }}
        />
        <Typography variant="h6" component="span">
          Authenticate {info.name}
        </Typography>
        <IconButton
          onClick={onClose}
          sx={{ position: 'absolute', right: 8, top: 8, color: 'text.secondary' }}
          aria-label="close"
        >
          <CloseIcon />
        </IconButton>
      </DialogTitle>

      <DialogContent sx={{ p: 0, overflow: 'hidden' }}>
        <Box sx={{ height: '100%' }}>
          <AgentAuthTerminal
            agentType={agentType}
            onAuthComplete={() => onAuthComplete(agentType)}
            onCancel={onClose}
          />
        </Box>
      </DialogContent>
    </Dialog>
  );
};
