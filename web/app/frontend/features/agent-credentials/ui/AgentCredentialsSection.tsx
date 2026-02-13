import CheckCircleIcon from '@mui/icons-material/CheckCircle';
import RadioButtonUncheckedIcon from '@mui/icons-material/RadioButtonUnchecked';
import RefreshIcon from '@mui/icons-material/Refresh';
import { Box, Button, Card, CardContent, Chip, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useSnackbar } from 'notistack';
import { useCallback, useRef, useState, type FC } from 'react';

import type { AgentType, IAgentCredential } from 'entities/user';
import { AGENT_COLORS, AVAILABLE_AGENTS, getAgentInfo, useGetCurrentUserQuery } from 'entities/user';

import { AgentAuthDialog } from './AgentAuthDialog';

const CREDENTIAL_POLL_INTERVAL_MS = 500;
const CREDENTIAL_POLL_MAX_ATTEMPTS = 20;

const styles = {
  section: {
    marginTop: '32px',
  },
  sectionTitle: {
    fontSize: '20px',
    fontWeight: 600,
    color: 'text.primary',
    marginBottom: '8px',
  },
  sectionDescription: {
    fontSize: '14px',
    color: 'text.secondary',
    marginBottom: '16px',
  },
  agentCard: {
    marginBottom: '12px',
    backgroundColor: 'background.paper',
    border: '1px solid',
    borderColor: 'divider',
    transition: 'border-color 0.2s ease',
  },
  agentCardContent: {
    display: 'flex',
    alignItems: 'center',
    gap: '16px',
    padding: '16px !important',
  },
  colorBar: {
    width: 4,
    height: 40,
    borderRadius: 1,
    flexShrink: 0,
  },
  agentInfo: {
    flex: 1,
    minWidth: 0,
  },
  agentName: {
    fontSize: '16px',
    fontWeight: 600,
    color: 'text.primary',
  },
  agentDescription: {
    fontSize: '13px',
    color: 'text.secondary',
    lineHeight: 1.4,
  },
  credentialMeta: {
    fontSize: '11px',
    color: 'text.disabled',
    marginTop: '4px',
  },
  actions: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    flexShrink: 0,
  },
} satisfies Record<string, SxProps<Theme>>;

const formatDate = (dateStr: string | null): string => {
  if (!dateStr) return '';
  const date = new Date(dateStr);
  return date.toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
};

export const AgentCredentialsSection: FC = () => {
  const { enqueueSnackbar } = useSnackbar();
  const { data: currentUser, refetch } = useGetCurrentUserQuery();
  const [authAgent, setAuthAgent] = useState<AgentType | null>(null);
  const [savingAgent, setSavingAgent] = useState<AgentType | null>(null);
  const pollIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const configuredAgents = currentUser?.configuredAgents ?? [];
  const credentialsMap = (currentUser?.agentCredentials ?? []).reduce<Record<string, IAgentCredential>>(
    (acc, cred) => {
      acc[cred.agentType] = cred;
      return acc;
    },
    {},
  );

  const handleAuthComplete = useCallback(
    (agentType: AgentType) => {
      setAuthAgent(null);
      setSavingAgent(agentType);
      enqueueSnackbar(`${getAgentInfo(agentType).name} — saving credentials...`, { variant: 'info' });

      if (pollIntervalRef.current) {
        clearInterval(pollIntervalRef.current);
      }

      let attempts = 0;
      pollIntervalRef.current = setInterval(async () => {
        attempts++;
        const result = await refetch();
        const agents = result.data?.configuredAgents ?? [];

        if (agents.includes(agentType)) {
          clearInterval(pollIntervalRef.current!);
          pollIntervalRef.current = null;
          setSavingAgent(null);
          enqueueSnackbar(`${getAgentInfo(agentType).name} authenticated!`, { variant: 'success' });
        } else if (attempts >= CREDENTIAL_POLL_MAX_ATTEMPTS) {
          clearInterval(pollIntervalRef.current!);
          pollIntervalRef.current = null;
          setSavingAgent(null);
          enqueueSnackbar(`${getAgentInfo(agentType).name} — failed to save credentials`, { variant: 'error' });
        }
      }, CREDENTIAL_POLL_INTERVAL_MS);
    },
    [refetch, enqueueSnackbar],
  );

  const handleDialogClose = () => {
    setAuthAgent(null);
  };

  return (
    <>
      <Box sx={styles.section}>
        <Typography sx={styles.sectionTitle}>Agent Runtimes</Typography>
        <Typography sx={styles.sectionDescription}>
          Manage authentication for AI coding agents. Authenticate new agents or re-authenticate existing ones.
        </Typography>

        {AVAILABLE_AGENTS.map((agent) => {
          const isConfigured = configuredAgents.includes(agent.type);
          const credential = credentialsMap[agent.type];
          const isSaving = savingAgent === agent.type;

          return (
            <Card key={agent.type} sx={styles.agentCard}>
              <CardContent sx={styles.agentCardContent}>
                <Box sx={{ ...styles.colorBar, backgroundColor: AGENT_COLORS[agent.type] }} />

                {isConfigured ? (
                  <CheckCircleIcon sx={{ color: 'success.main', fontSize: 24 }} />
                ) : (
                  <RadioButtonUncheckedIcon sx={{ color: 'text.disabled', fontSize: 24 }} />
                )}

                <Box sx={styles.agentInfo}>
                  <Typography sx={styles.agentName}>{agent.name}</Typography>
                  <Typography sx={styles.agentDescription}>{agent.description}</Typography>
                  {isConfigured && credential && (
                    <Typography sx={styles.credentialMeta}>
                      Configured {formatDate(credential.createdAt)}
                      {credential.lastUsedAt && ` · Last used ${formatDate(credential.lastUsedAt)}`}
                      {credential.expiresAt && ` · Expires ${formatDate(credential.expiresAt)}`}
                    </Typography>
                  )}
                </Box>

                <Box sx={styles.actions}>
                  {isConfigured && (
                    <Chip label="Connected" color="success" size="small" variant="outlined" />
                  )}

                  <Button
                    variant={isConfigured ? 'outlined' : 'contained'}
                    size="small"
                    onClick={() => setAuthAgent(agent.type)}
                    disabled={isSaving}
                    startIcon={isConfigured ? <RefreshIcon /> : undefined}
                    sx={{ textTransform: 'none', whiteSpace: 'nowrap' }}
                  >
                    {isSaving ? 'Saving...' : isConfigured ? 'Re-authenticate' : 'Authenticate'}
                  </Button>
                </Box>
              </CardContent>
            </Card>
          );
        })}
      </Box>

      <AgentAuthDialog
        open={authAgent !== null}
        agentType={authAgent}
        onClose={handleDialogClose}
        onAuthComplete={handleAuthComplete}
      />
    </>
  );
};
