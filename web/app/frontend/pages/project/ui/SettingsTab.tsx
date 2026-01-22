import {
  Box,
  Button,
  Card,
  Divider,
  IconButton,
  Switch,
  Tab,
  Tabs,
  TextField,
  Tooltip,
  Typography,
} from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useSnackbar } from 'notistack';
import { useState } from 'react';

import { CostAnalytics } from 'features/cost-analytics';
import { MCPConfigPanel } from 'features/mcp-config';
import { ToolConfigPanel } from 'features/tools-config';

interface IIntegration {
  id: string;
  name: string;
  description: string;
  icon: string;
  connected: boolean;
  connectUrl?: string;
}

interface IBillingPeriod {
  period: string;
  cost: number;
  tokens: number;
  requests: number;
}

const mockIntegrations: IIntegration[] = [
  {
    id: 'linear',
    name: 'Linear',
    description: 'Import tasks and sync project status',
    icon: '📋',
    connected: false,
    connectUrl: '/integrations/linear/connect',
  },
  {
    id: 'github',
    name: 'GitHub',
    description: 'Create PRs, access repositories, code context',
    icon: '🐙',
    connected: true,
    connectUrl: '/integrations/github/connect',
  },
  {
    id: 'gitlab',
    name: 'GitLab',
    description: 'Create MRs, access repositories',
    icon: '🦊',
    connected: false,
    connectUrl: '/integrations/gitlab/connect',
  },
];

const mockBillingData: IBillingPeriod[] = [
  { period: 'This Month', cost: 1247.50, tokens: 1250000, requests: 3420 },
  { period: 'Last Month', cost: 1890.25, tokens: 1890000, requests: 5120 },
  { period: 'This Year', cost: 15234.80, tokens: 15200000, requests: 45600 },
];

const styles = {
  container: {
    padding: '32px',
    maxWidth: '1000px',
  },
  section: {
    marginBottom: '48px',
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
    marginBottom: '24px',
  },
  card: {
    padding: '24px',
    backgroundColor: 'background.paper',
    borderRadius: '12px',
    border: '1px solid',
    borderColor: 'divider',
  },
  formField: {
    marginBottom: '20px',
  },
  label: {
    fontSize: '14px',
    fontWeight: 500,
    color: 'text.primary',
    marginBottom: '8px',
  },
  input: {
    '& .MuiOutlinedInput-root': {
      backgroundColor: 'background.elevated',
    },
  },
  integrationsGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))',
    gap: '16px',
  },
  integrationCard: {
    padding: '20px',
    backgroundColor: 'background.paper',
    borderRadius: '12px',
    border: '1px solid',
    borderColor: 'divider',
    transition: 'all 0.2s ease',
    '&:hover': {
      borderColor: 'primary.main',
    },
  },
  integrationCardConnected: {
    borderColor: 'success.main',
    backgroundColor: 'rgba(16, 163, 127, 0.05)',
  },
  integrationHeader: {
    display: 'flex',
    alignItems: 'flex-start',
    justifyContent: 'space-between',
    marginBottom: '12px',
  },
  integrationIcon: {
    fontSize: '32px',
    marginBottom: '8px',
  },
  integrationName: {
    fontSize: '16px',
    fontWeight: 600,
    color: 'text.primary',
    marginBottom: '4px',
  },
  integrationDescription: {
    fontSize: '13px',
    color: 'text.secondary',
    lineHeight: 1.5,
  },
  badge: {
    padding: '4px 8px',
    borderRadius: '4px',
    fontSize: '11px',
    fontWeight: 600,
    textTransform: 'uppercase',
  },
  badgeConnected: {
    backgroundColor: 'success.main',
    color: 'white',
  },
  badgeDisconnected: {
    backgroundColor: 'background.elevated',
    color: 'text.secondary',
  },
  connectButton: {
    marginTop: '12px',
    textTransform: 'none',
    width: '100%',
  },
  disconnectButton: {
    marginTop: '12px',
    textTransform: 'none',
    width: '100%',
    color: 'error.main',
    borderColor: 'error.main',
    '&:hover': {
      borderColor: 'error.dark',
      backgroundColor: 'rgba(244, 71, 71, 0.08)',
    },
  },
  billingGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))',
    gap: '16px',
    marginBottom: '24px',
  },
  billingCard: {
    padding: '20px',
    backgroundColor: 'background.paper',
    borderRadius: '12px',
    border: '1px solid',
    borderColor: 'divider',
  },
  billingPeriod: {
    fontSize: '13px',
    color: 'text.secondary',
    marginBottom: '12px',
  },
  billingAmount: {
    fontSize: '28px',
    fontWeight: 700,
    color: 'text.primary',
    marginBottom: '8px',
  },
  billingDetails: {
    fontSize: '12px',
    color: 'text.secondary',
    display: 'flex',
    flexDirection: 'column',
    gap: '4px',
  },
  saveButton: {
    minWidth: '120px',
    textTransform: 'none',
  },
  divider: {
    margin: '24px 0',
  },
} satisfies Record<string, SxProps<Theme>>;

interface SettingsTabProps {
  projectId: string;
}

const SettingsTab = ({ projectId }: SettingsTabProps) => {
  const { enqueueSnackbar } = useSnackbar();
  const [projectName, setProjectName] = useState('Palad Platform');
  const [projectDescription, setProjectDescription] = useState('AI coding agents orchestration platform');
  const [integrations, setIntegrations] = useState<IIntegration[]>(mockIntegrations);
  const [autoSyncLinear, setAutoSyncLinear] = useState(false);
  const [autoCreatePRs, setAutoCreatePRs] = useState(true);

  const handleSaveProject = () => {
    enqueueSnackbar('Project settings saved', { variant: 'success' });
  };

  const handleConnectIntegration = (integrationId: string) => {
    setIntegrations((prev) =>
      prev.map((int) => (int.id === integrationId ? { ...int, connected: true } : int)),
    );
    enqueueSnackbar(`${integrations.find((i) => i.id === integrationId)?.name} connected!`, {
      variant: 'success',
    });
  };

  const handleDisconnectIntegration = (integrationId: string) => {
    setIntegrations((prev) =>
      prev.map((int) => (int.id === integrationId ? { ...int, connected: false } : int)),
    );
    enqueueSnackbar(`${integrations.find((i) => i.id === integrationId)?.name} disconnected`, {
      variant: 'info',
    });
  };

  return (
    <Box sx={styles.container}>
      {/* Project Settings */}
      <Box sx={styles.section}>
        <Typography sx={styles.sectionTitle}>Project Settings</Typography>
        <Typography sx={styles.sectionDescription}>
          Configure your project name, description, and basic settings.
        </Typography>

        <Box sx={styles.card}>
          <Box sx={styles.formField}>
            <Typography sx={styles.label}>Project Name</Typography>
            <TextField
              fullWidth
              size="small"
              value={projectName}
              onChange={(e) => setProjectName(e.target.value)}
              placeholder="Enter project name"
              sx={styles.input}
            />
          </Box>

          <Box sx={styles.formField}>
            <Typography sx={styles.label}>Description</Typography>
            <TextField
              fullWidth
              multiline
              rows={3}
              value={projectDescription}
              onChange={(e) => setProjectDescription(e.target.value)}
              placeholder="Enter project description"
              sx={styles.input}
            />
          </Box>

          <Box sx={{ display: 'flex', justifyContent: 'flex-end', marginTop: '24px' }}>
            <Button variant="contained" sx={styles.saveButton} onClick={handleSaveProject}>
              Save Changes
            </Button>
          </Box>
        </Box>
      </Box>

      <Divider sx={styles.divider} />

      {/* Integrations */}
      <Box sx={styles.section}>
        <Typography sx={styles.sectionTitle}>Integrations</Typography>
        <Typography sx={styles.sectionDescription}>
          Connect external services to enhance your workflow automation.
        </Typography>

        <Box sx={styles.integrationsGrid}>
          {integrations.map((integration) => (
            <Box
              key={integration.id}
              sx={{
                ...styles.integrationCard,
                ...(integration.connected ? styles.integrationCardConnected : {}),
              }}
            >
              <Box sx={styles.integrationHeader}>
                <Box>
                  <Typography sx={styles.integrationIcon}>{integration.icon}</Typography>
                  <Typography sx={styles.integrationName}>{integration.name}</Typography>
                </Box>
                <Box
                  sx={{
                    ...styles.badge,
                    ...(integration.connected ? styles.badgeConnected : styles.badgeDisconnected),
                  }}
                >
                  {integration.connected ? 'Connected' : 'Not Connected'}
                </Box>
              </Box>

              <Typography sx={styles.integrationDescription}>{integration.description}</Typography>

              {integration.connected ? (
                <>
                  {integration.id === 'linear' && (
                    <Box sx={{ marginTop: '12px' }}>
                      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '8px' }}>
                        <Typography sx={{ fontSize: '13px', color: 'text.secondary' }}>
                          Auto-sync tasks
                        </Typography>
                        <Switch
                          size="small"
                          checked={autoSyncLinear}
                          onChange={(e) => setAutoSyncLinear(e.target.checked)}
                        />
                      </Box>
                    </Box>
                  )}
                  {integration.id === 'github' && (
                    <Box sx={{ marginTop: '12px' }}>
                      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: '8px' }}>
                        <Typography sx={{ fontSize: '13px', color: 'text.secondary' }}>
                          Auto-create PRs
                        </Typography>
                        <Switch
                          size="small"
                          checked={autoCreatePRs}
                          onChange={(e) => setAutoCreatePRs(e.target.checked)}
                        />
                      </Box>
                    </Box>
                  )}
                  <Button
                    variant="outlined"
                    sx={styles.disconnectButton}
                    onClick={() => handleDisconnectIntegration(integration.id)}
                  >
                    Disconnect
                  </Button>
                </>
              ) : (
                <Button
                  variant="contained"
                  sx={styles.connectButton}
                  onClick={() => handleConnectIntegration(integration.id)}
                >
                  Connect
                </Button>
              )}
            </Box>
          ))}
        </Box>
      </Box>

      <Divider sx={styles.divider} />

      {/* Billing & Usage */}
      <Box sx={styles.section}>
        <Typography sx={styles.sectionTitle}>Billing & Usage</Typography>
        <Typography sx={styles.sectionDescription}>
          Track your project's token usage and costs across all workflows.
        </Typography>

        <CostAnalytics projectId={projectId} />
      </Box>

      <Divider sx={styles.divider} />

      {/* Agent Tools Configuration */}
      <Box sx={styles.section}>
        <Typography sx={styles.sectionTitle}>Agent Tools</Typography>
        <Typography sx={styles.sectionDescription}>
          Configure which tools each agent can use during workflow execution.
        </Typography>

        <ToolConfigPanel agentType="claude_code" />
      </Box>

      <Divider sx={styles.divider} />

      {/* MCP Servers Configuration */}
      <Box sx={styles.section}>
        <Typography sx={styles.sectionTitle}>MCP Servers</Typography>
        <Typography sx={styles.sectionDescription}>
          Configure Model Context Protocol servers to provide tools and resources to agents.
        </Typography>

        <MCPConfigPanel />
      </Box>
    </Box>
  );
};

export default SettingsTab;
