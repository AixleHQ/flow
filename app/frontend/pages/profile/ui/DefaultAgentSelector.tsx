import {
  Card,
  CardContent,
  CircularProgress,
  FormControl,
  InputLabel,
  MenuItem,
  Select,
  Typography,
} from '@mui/material';
import { enqueueSnackbar } from 'notistack';

import { AVAILABLE_AGENTS, useGetCurrentUserQuery, useUpdateCurrentUserMutation, type AgentType } from 'entities/user';

export const DefaultAgentSelector: React.FC = () => {
  const { data: currentUser } = useGetCurrentUserQuery();
  const [updateUser, { isLoading }] = useUpdateCurrentUserMutation();

  if (!currentUser) return null;

  const credentials = currentUser.agentCredentials ?? [];

  const handleChange = async (credentialId: number) => {
    try {
      await updateUser({
        currentUser: { defaultAgentCredentialId: credentialId },
      }).unwrap();
      enqueueSnackbar('Default agent updated', { variant: 'success' });
    } catch {
      enqueueSnackbar('Failed to update default agent', { variant: 'error' });
    }
  };

  if (credentials.length === 0) {
    return (
      <Card sx={{ mt: 3, backgroundColor: 'background.paper' }}>
        <CardContent>
          <Typography variant="subtitle1" fontWeight={600} gutterBottom>
            Default Agent Runtime
          </Typography>
          <Typography variant="body2" color="text.secondary">
            No agent credentials configured. Complete onboarding to set up agents.
          </Typography>
        </CardContent>
      </Card>
    );
  }

  const agentLabel = (agentType: AgentType) => AVAILABLE_AGENTS.find((a) => a.type === agentType)?.name ?? agentType;

  return (
    <Card sx={{ mt: 3, backgroundColor: 'background.paper' }}>
      <CardContent>
        <Typography variant="subtitle1" fontWeight={600} gutterBottom>
          Default Agent Runtime
        </Typography>
        <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
          Used when starting new sessions and as fallback for workflow execution.
        </Typography>
        <FormControl fullWidth size="small">
          <InputLabel>Default Agent</InputLabel>
          <Select
            value={currentUser.defaultAgentCredentialId ?? ''}
            label="Default Agent"
            onChange={(e) => handleChange(e.target.value as number)}
            disabled={isLoading || credentials.length <= 1}
            endAdornment={isLoading ? <CircularProgress size={20} sx={{ mr: 2 }} /> : undefined}
          >
            {credentials.map((cred) => (
              <MenuItem key={cred.id} value={cred.id}>
                {agentLabel(cred.agentType)}
              </MenuItem>
            ))}
          </Select>
        </FormControl>
      </CardContent>
    </Card>
  );
};
