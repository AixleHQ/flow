import { Box, Button, Card, IconButton, TextField, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useSnackbar } from 'notistack';
import { useState } from 'react';

interface IMCPSecret {
  name: string;
  value: string;
}

interface IMCPServer {
  id: string;
  name: string;
  description: string;
  transport: 'stdio' | 'sse' | 'websocket';
  command: string;
  args?: string[];
  env?: Record<string, string>;
  secrets: IMCPSecret[];
}

const styles = {
  container: {
    padding: '24px',
    maxWidth: '1000px',
  },
  header: {
    marginBottom: '24px',
  },
  title: {
    fontSize: '20px',
    fontWeight: 600,
    color: 'text.primary',
    marginBottom: '8px',
  },
  description: {
    fontSize: '14px',
    color: 'text.secondary',
  },
  card: {
    padding: '20px',
    backgroundColor: 'background.paper',
    borderRadius: '12px',
    border: '1px solid',
    borderColor: 'divider',
    marginBottom: '20px',
  },
  cardTitle: {
    fontSize: '16px',
    fontWeight: 600,
    color: 'text.primary',
    marginBottom: '16px',
  },
  formField: {
    marginBottom: '16px',
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
  select: {
    '& .MuiOutlinedInput-root': {
      backgroundColor: 'background.elevated',
    },
  },
  secretsList: {
    display: 'flex',
    flexDirection: 'column',
    gap: '12px',
  },
  secretCard: {
    padding: '12px',
    backgroundColor: 'background.elevated',
    borderRadius: '8px',
    border: '1px solid',
    borderColor: 'divider',
  },
  secretRow: {
    display: 'flex',
    gap: '8px',
    alignItems: 'center',
  },
  addSecretButton: {
    marginTop: '8px',
    textTransform: 'none',
  },
  argsList: {
    display: 'flex',
    flexDirection: 'column',
    gap: '8px',
    marginTop: '8px',
  },
  argRow: {
    display: 'flex',
    gap: '8px',
    alignItems: 'center',
  },
  addArgButton: {
    marginTop: '8px',
    textTransform: 'none',
  },
  actions: {
    display: 'flex',
    justifyContent: 'flex-end',
    gap: '12px',
    marginTop: '24px',
    paddingTop: '24px',
    borderTop: '1px solid',
    borderColor: 'divider',
  },
  saveButton: {
    minWidth: '120px',
    textTransform: 'none',
  },
  testButton: {
    textTransform: 'none',
  },
} satisfies Record<string, SxProps<Theme>>;

interface MCPConfigPanelProps {
  onSave?: (server: IMCPServer) => void;
}

const TRANSPORT_OPTIONS = [
  { value: 'stdio', label: 'stdio', description: 'Standard input/output' },
  { value: 'sse', label: 'SSE', description: 'Server-Sent Events' },
  { value: 'websocket', label: 'WebSocket', description: 'WebSocket connection' },
];

const MCPConfigPanel = ({ onSave }: MCPConfigPanelProps) => {
  const { enqueueSnackbar } = useSnackbar();
  const [server, setServer] = useState<IMCPServer>({
    id: 'new-mcp-server',
    name: '',
    description: '',
    transport: 'stdio',
    command: '',
    args: [],
    env: {},
    secrets: [],
  });

  const handleAddSecret = () => {
    setServer((prev) => ({
      ...prev,
      secrets: [...prev.secrets, { name: '', value: '' }],
    }));
  };

  const handleUpdateSecret = (index: number, updates: Partial<IMCPSecret>) => {
    setServer((prev) => ({
      ...prev,
      secrets: prev.secrets.map((s, i) => (i === index ? { ...s, ...updates } : s)),
    }));
  };

  const handleRemoveSecret = (index: number) => {
    setServer((prev) => ({
      ...prev,
      secrets: prev.secrets.filter((_, i) => i !== index),
    }));
  };

  const handleAddArg = () => {
    setServer((prev) => ({
      ...prev,
      args: [...(prev.args || []), ''],
    }));
  };

  const handleUpdateArg = (index: number, value: string) => {
    setServer((prev) => ({
      ...prev,
      args: prev.args?.map((a, i) => (i === index ? value : a)) || [],
    }));
  };

  const handleRemoveArg = (index: number) => {
    setServer((prev) => ({
      ...prev,
      args: prev.args?.filter((_, i) => i !== index) || [],
    }));
  };

  const handleTest = () => {
    if (!server.name || !server.command) {
      enqueueSnackbar('Please fill in server name and command', { variant: 'warning' });
      return;
    }
    enqueueSnackbar('Testing MCP server connection...', { variant: 'info' });
    // In real app, this would test the MCP server connection
  };

  const handleSave = () => {
    if (!server.name || !server.command) {
      enqueueSnackbar('Please fill in server name and command', { variant: 'warning' });
      return;
    }
    onSave?.(server);
    enqueueSnackbar('MCP server configuration saved', { variant: 'success' });
  };

  return (
    <Box sx={styles.container}>
      <Box sx={styles.header}>
        <Typography sx={styles.title}>Configure MCP Server</Typography>
        <Typography sx={styles.description}>
          Model Context Protocol (MCP) servers provide tools and resources to agents. Configure connection details and
          secrets.
        </Typography>
      </Box>

      {/* Basic Information */}
      <Card sx={styles.card}>
        <Typography sx={styles.cardTitle}>Basic Information</Typography>
        <Box sx={styles.formField}>
          <Typography sx={styles.label}>Server Name</Typography>
          <TextField
            fullWidth
            size="small"
            value={server.name}
            onChange={(e) => setServer({ ...server, name: e.target.value })}
            placeholder="e.g., Database Connector"
            sx={styles.input}
          />
        </Box>
        <Box sx={styles.formField}>
          <Typography sx={styles.label}>Description</Typography>
          <TextField
            fullWidth
            multiline
            rows={2}
            value={server.description}
            onChange={(e) => setServer({ ...server, description: e.target.value })}
            placeholder="What does this MCP server provide?"
            sx={styles.input}
          />
        </Box>
        <Box sx={styles.formField}>
          <Typography sx={styles.label}>Transport</Typography>
          <Box sx={{ display: 'flex', gap: '12px', flexWrap: 'wrap' }}>
            {TRANSPORT_OPTIONS.map((transport) => (
              <Button
                key={transport.value}
                variant={server.transport === transport.value ? 'contained' : 'outlined'}
                size="small"
                onClick={() => setServer({ ...server, transport: transport.value as 'stdio' | 'sse' | 'websocket' })}
                sx={{ textTransform: 'none' }}
              >
                {transport.label}
              </Button>
            ))}
          </Box>
          <Typography sx={{ fontSize: '12px', color: 'text.disabled', marginTop: '4px' }}>
            {TRANSPORT_OPTIONS.find((t) => t.value === server.transport)?.description}
          </Typography>
        </Box>
      </Card>

      {/* Command & Arguments */}
      <Card sx={styles.card}>
        <Typography sx={styles.cardTitle}>Command & Arguments</Typography>
        <Box sx={styles.formField}>
          <Typography sx={styles.label}>Command</Typography>
          <TextField
            fullWidth
            size="small"
            value={server.command}
            onChange={(e) => setServer({ ...server, command: e.target.value })}
            placeholder="e.g., npx, python, node"
            sx={styles.input}
          />
        </Box>
        {server.args && server.args.length > 0 && (
          <Box sx={styles.argsList}>
            {server.args.map((arg, index) => (
              <Box key={index} sx={styles.argRow}>
                <TextField
                  size="small"
                  placeholder="Argument"
                  value={arg}
                  onChange={(e) => handleUpdateArg(index, e.target.value)}
                  sx={{ ...styles.input, flex: 1 }}
                />
                <IconButton size="small" onClick={() => handleRemoveArg(index)} sx={{ color: 'error.main' }}>
                  ✕
                </IconButton>
              </Box>
            ))}
          </Box>
        )}
        <Button variant="outlined" size="small" sx={styles.addArgButton} onClick={handleAddArg}>
          + Add Argument
        </Button>
      </Card>

      {/* Secrets */}
      <Card sx={styles.card}>
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
          <Typography sx={styles.cardTitle}>Secrets</Typography>
        </Box>
        <Typography sx={{ fontSize: '13px', color: 'text.secondary', marginBottom: '12px' }}>
          Environment variables available to the MCP server (e.g., DATABASE_URL, API_KEY)
        </Typography>
        <Box sx={styles.secretsList}>
          {server.secrets.map((secret, index) => (
            <Box key={index} sx={styles.secretCard}>
              <Box sx={styles.secretRow}>
                <TextField
                  size="small"
                  placeholder="DATABASE_URL"
                  value={secret.name}
                  onChange={(e) => handleUpdateSecret(index, { name: e.target.value.toUpperCase() })}
                  sx={{ ...styles.input, flex: 1 }}
                  inputProps={{ style: { textTransform: 'uppercase' } }}
                />
                <Typography sx={{ fontSize: '14px', color: 'text.secondary' }}>=</Typography>
                <TextField
                  size="small"
                  type="password"
                  placeholder="secret value"
                  value={secret.value}
                  onChange={(e) => handleUpdateSecret(index, { value: e.target.value })}
                  sx={{ ...styles.input, flex: 1 }}
                />
                <IconButton size="small" onClick={() => handleRemoveSecret(index)} sx={{ color: 'error.main' }}>
                  ✕
                </IconButton>
              </Box>
            </Box>
          ))}
        </Box>
        <Button variant="outlined" size="small" sx={styles.addSecretButton} onClick={handleAddSecret}>
          + Add Secret
        </Button>
      </Card>

      <Box sx={styles.actions}>
        <Button
          variant="outlined"
          sx={styles.testButton}
          onClick={handleTest}
          disabled={!server.name || !server.command}
        >
          Test Connection
        </Button>
        <Button
          variant="contained"
          sx={styles.saveButton}
          onClick={handleSave}
          disabled={!server.name || !server.command}
        >
          Save Server
        </Button>
      </Box>
    </Box>
  );
};

export default MCPConfigPanel;
