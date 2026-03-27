import { Autocomplete, Box, Card, CardContent, CircularProgress, Stack, TextField, Typography } from '@mui/material';
import { enqueueSnackbar } from 'notistack';
import { useCallback, useState } from 'react';

import { AVAILABLE_AGENTS, useGetCurrentUserQuery, type IAgentCredential } from 'entities/user';
import type { AgentModel } from 'shared/api/agentModelsApi';
import { useLazyGetAgentModelsQuery, useUpdateDefaultModelMutation } from 'shared/api/agentModelsApi';

function CredentialModelRow({ credential }: { credential: IAgentCredential }) {
  const [fetchModels, { data: models, isFetching }] = useLazyGetAgentModelsQuery();
  const [updateDefaultModel] = useUpdateDefaultModelMutation();
  const [fetched, setFetched] = useState(false);

  const agentLabel = AVAILABLE_AGENTS.find((a) => a.type === credential.agentType)?.name ?? credential.agentType;

  const modelsList = Array.isArray(models) ? models : [];
  // Before models are loaded, show saved model ID as a placeholder option
  const currentModel = credential.defaultModel
    ? (modelsList.find((m) => m.modelId === credential.defaultModel) ??
      (fetched ? null : { modelId: credential.defaultModel, displayName: credential.defaultModel, description: '' }))
    : null;

  const handleOpen = useCallback(() => {
    if (!fetched) {
      fetchModels(credential.agentType);
      setFetched(true);
    }
  }, [fetched, fetchModels, credential.agentType]);

  const handleChange = useCallback(
    async (_: unknown, value: AgentModel | null) => {
      try {
        await updateDefaultModel({
          agentCredentialId: credential.id,
          defaultModel: value?.modelId ?? null,
        }).unwrap();
        enqueueSnackbar(`Default model ${value ? `set to ${value.displayName}` : 'cleared'} for ${agentLabel}`, {
          variant: 'success',
        });
      } catch {
        enqueueSnackbar('Failed to update default model', { variant: 'error' });
      }
    },
    [credential.id, agentLabel, updateDefaultModel],
  );

  return (
    <Stack direction="row" alignItems="center" spacing={2}>
      <Typography variant="body2" sx={{ minWidth: 120, fontWeight: 500 }}>
        {agentLabel}
      </Typography>
      <Autocomplete
        size="small"
        options={modelsList}
        getOptionLabel={(o) => o.displayName}
        value={currentModel}
        onChange={handleChange}
        onOpen={handleOpen}
        loading={isFetching}
        renderInput={(params) => (
          <TextField
            {...params}
            placeholder="Default (runtime selects)"
            slotProps={{
              input: {
                ...params.InputProps,
                endAdornment: (
                  <>
                    {isFetching ? <CircularProgress color="inherit" size={18} /> : null}
                    {params.InputProps.endAdornment}
                  </>
                ),
              },
            }}
          />
        )}
        renderOption={(props, option) => (
          <li {...props} key={option.modelId}>
            <Box>
              <Typography variant="body2">{option.displayName}</Typography>
              {option.description && (
                <Typography variant="caption" color="text.secondary">
                  {option.description}
                </Typography>
              )}
            </Box>
          </li>
        )}
        isOptionEqualToValue={(o, v) => o.modelId === v.modelId}
        sx={{ flex: 1 }}
      />
    </Stack>
  );
}

export const DefaultModelSelector: React.FC = () => {
  const { data: currentUser } = useGetCurrentUserQuery();

  if (!currentUser) return null;

  const credentials = currentUser.agentCredentials ?? [];
  if (credentials.length === 0) return null;

  return (
    <Card sx={{ mt: 3, backgroundColor: 'background.paper' }}>
      <CardContent>
        <Typography variant="subtitle1" fontWeight={600} gutterBottom>
          Default Models
        </Typography>
        <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
          Set a preferred model per agent runtime. Used when no model is specified in session or workflow step.
        </Typography>
        <Stack spacing={2}>
          {credentials.map((cred) => (
            <CredentialModelRow key={cred.id} credential={cred} />
          ))}
        </Stack>
      </CardContent>
    </Card>
  );
};
