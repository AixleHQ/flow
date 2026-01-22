import {
  Box,
  Button,
  Card,
  Chip,
  Divider,
  IconButton,
  MenuItem,
  Select,
  TextField,
  Typography,
} from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useSnackbar } from 'notistack';
import { useState } from 'react';

interface IToolSecret {
  name: string;
  value: string;
}

interface IToolFile {
  name: string;
  content: string;
}

interface ITool {
  id: string;
  name: string;
  description: string;
  language: 'node' | 'ruby' | 'python' | 'go' | 'java';
  command: string;
  secrets: IToolSecret[];
  files: IToolFile[];
}

const styles = {
  container: {
    padding: '24px',
    maxWidth: '1200px',
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
  twoColumnLayout: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr',
    gap: '24px',
    marginBottom: '24px',
  },
  configPanel: {
    display: 'flex',
    flexDirection: 'column',
    gap: '20px',
  },
  card: {
    padding: '20px',
    backgroundColor: 'background.paper',
    borderRadius: '12px',
    border: '1px solid',
    borderColor: 'divider',
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
  languageChip: {
    fontSize: '12px',
    fontWeight: 600,
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
  filesSection: {
    marginTop: '20px',
  },
  filesList: {
    display: 'flex',
    flexDirection: 'column',
    gap: '8px',
    marginBottom: '12px',
  },
  fileItem: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
    padding: '8px 12px',
    backgroundColor: 'background.elevated',
    borderRadius: '6px',
    border: '1px solid',
    borderColor: 'divider',
  },
  fileItemActive: {
    borderColor: 'primary.main',
    backgroundColor: 'rgba(71, 133, 255, 0.08)',
  },
  fileName: {
    fontSize: '13px',
    color: 'text.primary',
    fontFamily: 'monospace',
  },
  fileEditor: {
    marginTop: '12px',
  },
  fileEditorHeader: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: '8px',
  },
  fileEditorTitle: {
    fontSize: '13px',
    fontWeight: 500,
    color: 'text.primary',
    fontFamily: 'monospace',
  },
  fileEditorContent: {
    '& .MuiOutlinedInput-root': {
      backgroundColor: 'background.elevated',
      fontFamily: 'monospace',
      fontSize: '13px',
    },
  },
  terminalContainer: {
    backgroundColor: '#0D0D0D',
    borderRadius: '12px',
    border: '1px solid',
    borderColor: 'divider',
    overflow: 'hidden',
    display: 'flex',
    flexDirection: 'column',
    minHeight: '600px',
  },
  terminalHeader: {
    padding: '12px 16px',
    backgroundColor: '#1A1A1A',
    borderBottom: '1px solid',
    borderColor: 'divider',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  terminalTitle: {
    fontSize: '14px',
    fontWeight: 500,
    color: 'text.primary',
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
  },
  terminalContent: {
    flex: 1,
    display: 'flex',
    overflow: 'hidden',
  },
  fileTree: {
    width: '250px',
    backgroundColor: '#1A1A1A',
    borderRight: '1px solid',
    borderColor: 'divider',
    overflow: 'auto',
    padding: '12px',
  },
  fileTreeHeader: {
    fontSize: '12px',
    fontWeight: 600,
    color: 'text.secondary',
    marginBottom: '12px',
    textTransform: 'uppercase',
  },
  fileItem: {
    padding: '6px 8px',
    borderRadius: '4px',
    fontSize: '13px',
    color: 'text.secondary',
    cursor: 'pointer',
    marginBottom: '4px',
    '&:hover': {
      backgroundColor: 'rgba(255, 255, 255, 0.05)',
    },
  },
  fileItemActive: {
    backgroundColor: 'rgba(71, 133, 255, 0.2)',
    color: 'text.primary',
  },
  terminalArea: {
    flex: 1,
    display: 'flex',
    flexDirection: 'column',
  },
  terminalIframe: {
    flex: 1,
    border: 'none',
    backgroundColor: '#0D0D0D',
  },
  terminalPlaceholder: {
    flex: 1,
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    color: 'text.secondary',
    gap: '16px',
    padding: '48px',
  },
  placeholderIcon: {
    fontSize: '48px',
  },
  placeholderText: {
    fontSize: '14px',
    textAlign: 'center',
  },
  actions: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginTop: '24px',
    paddingTop: '24px',
    borderTop: '1px solid',
    borderColor: 'divider',
  },
  testButton: {
    textTransform: 'none',
  },
  saveButton: {
    minWidth: '120px',
    textTransform: 'none',
  },
} satisfies Record<string, SxProps<Theme>>;

interface ToolConfigPanelProps {
  agentType?: string;
  onSave?: (tool: ITool) => void;
}

const LANGUAGES = [
  { value: 'node', label: 'Node.js', icon: '📦' },
  { value: 'ruby', label: 'Ruby', icon: '💎' },
  { value: 'python', label: 'Python', icon: '🐍' },
  { value: 'go', label: 'Go', icon: '🐹' },
  { value: 'java', label: 'Java', icon: '☕' },
];

const mockFiles = [
  { name: 'Gemfile', type: 'file', content: 'source "https://rubygems.org"\n\ngem "slack-ruby-client", "~> 2.0"' },
  { name: 'Gemfile.lock', type: 'file', content: 'GEM\n  specs:\n    slack-ruby-client (2.0.0)' },
  { name: 'script.rb', type: 'file', content: 'require "slack-ruby-client"\n\nSlack.configure do |config|\n  config.token = ENV["SLACK_TOKEN"]\nend\n\nclient = Slack::Web::Client.new\nclient.chat_postMessage(channel: "#general", text: "Hello from Palad!")' },
];

const ToolConfigPanel = ({ agentType: initialAgentType, onSave }: ToolConfigPanelProps) => {
  const { enqueueSnackbar } = useSnackbar();
  const [tool, setTool] = useState<ITool>({
    id: 'new-tool',
    name: '',
    description: '',
    language: 'ruby',
    command: '',
    secrets: [],
    files: [],
  });
  const [selectedFileIndex, setSelectedFileIndex] = useState<number | null>(null);
  const [selectedFileForView, setSelectedFileForView] = useState<string | null>(null);
  const [isTesting, setIsTesting] = useState(false);

  const handleAddSecret = () => {
    setTool((prev) => ({
      ...prev,
      secrets: [...prev.secrets, { name: '', value: '' }],
    }));
  };

  const handleUpdateSecret = (index: number, updates: Partial<IToolSecret>) => {
    setTool((prev) => ({
      ...prev,
      secrets: prev.secrets.map((s, i) => (i === index ? { ...s, ...updates } : s)),
    }));
  };

  const handleRemoveSecret = (index: number) => {
    setTool((prev) => ({
      ...prev,
      secrets: prev.secrets.filter((_, i) => i !== index),
    }));
  };

  const handleAddFile = () => {
    const fileName = prompt('Enter file name (e.g., script.rb):');
    if (fileName) {
      setTool((prev) => ({
        ...prev,
        files: [...prev.files, { name: fileName, content: '' }],
      }));
      setSelectedFileIndex(tool.files.length);
    }
  };

  const handleUpdateFile = (index: number, updates: Partial<IToolFile>) => {
    setTool((prev) => ({
      ...prev,
      files: prev.files.map((f, i) => (i === index ? { ...f, ...updates } : f)),
    }));
  };

  const handleRemoveFile = (index: number) => {
    setTool((prev) => ({
      ...prev,
      files: prev.files.filter((_, i) => i !== index),
    }));
    if (selectedFileIndex === index) {
      setSelectedFileIndex(null);
    } else if (selectedFileIndex !== null && selectedFileIndex > index) {
      setSelectedFileIndex(selectedFileIndex - 1);
    }
  };

  const handleTest = () => {
    if (!tool.name || !tool.command) {
      enqueueSnackbar('Please fill in tool name and command', { variant: 'warning' });
      return;
    }
    setIsTesting(true);
    enqueueSnackbar('Starting test session...', { variant: 'info' });
    // In real app, this would start a container session and get ttyd URL
  };

  const handleSave = () => {
    if (!tool.name || !tool.command) {
      enqueueSnackbar('Please fill in tool name and command', { variant: 'warning' });
      return;
    }
    onSave?.(tool);
    enqueueSnackbar('Tool configuration saved', { variant: 'success' });
  };

  const selectedLanguage = LANGUAGES.find((l) => l.value === tool.language);

  return (
    <Box sx={styles.container}>
      <Box sx={styles.header}>
        <Typography sx={styles.title}>Configure Custom Tool</Typography>
        <Typography sx={styles.description}>
          Configure secrets (environment variables), select language, set command, and test your tool in an interactive session.
        </Typography>
      </Box>

      <Box sx={styles.twoColumnLayout}>
        {/* Configuration Panel */}
        <Box sx={styles.configPanel}>
          {/* Basic Info */}
          <Card sx={styles.card}>
            <Typography sx={styles.cardTitle}>Basic Information</Typography>
            <Box sx={styles.formField}>
              <Typography sx={styles.label}>Tool Name</Typography>
              <TextField
                fullWidth
                size="small"
                value={tool.name}
                onChange={(e) => setTool({ ...tool, name: e.target.value })}
                placeholder="e.g., Slack Notifier"
                sx={styles.input}
              />
            </Box>
            <Box sx={styles.formField}>
              <Typography sx={styles.label}>Description</Typography>
              <TextField
                fullWidth
                multiline
                rows={2}
                value={tool.description}
                onChange={(e) => setTool({ ...tool, description: e.target.value })}
                placeholder="What does this tool do?"
                sx={styles.input}
              />
            </Box>
            <Box sx={styles.formField}>
              <Typography sx={styles.label}>Language</Typography>
              <Select
                fullWidth
                size="small"
                value={tool.language}
                onChange={(e) => setTool({ ...tool, language: e.target.value as any })}
                sx={styles.select}
              >
                {LANGUAGES.map((lang) => (
                  <MenuItem key={lang.value} value={lang.value}>
                    {lang.icon} {lang.label}
                  </MenuItem>
                ))}
              </Select>
            </Box>
            <Box sx={styles.formField}>
              <Typography sx={styles.label}>Command</Typography>
              <TextField
                fullWidth
                size="small"
                value={tool.command}
                onChange={(e) => setTool({ ...tool, command: e.target.value })}
                placeholder={tool.language === 'ruby' ? 'ruby script.rb' : tool.language === 'node' ? 'node script.js' : 'python script.py'}
                sx={styles.input}
              />
            </Box>
          </Card>

          {/* Secrets */}
          <Card sx={styles.card}>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
              <Typography sx={styles.cardTitle}>Secrets</Typography>
            </Box>
            <Typography sx={{ fontSize: '13px', color: 'text.secondary', marginBottom: '12px' }}>
              Environment variables available to your tool (e.g., SLACK_TOKEN, API_KEY)
            </Typography>
            <Box sx={styles.secretsList}>
              {tool.secrets.map((secret, index) => (
                <Box key={index} sx={styles.secretCard}>
                  <Box sx={styles.secretRow}>
                    <TextField
                      size="small"
                      placeholder="SLACK_TOKEN"
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
                    <IconButton
                      size="small"
                      onClick={() => handleRemoveSecret(index)}
                      sx={{ color: 'error.main' }}
                    >
                      ✕
                    </IconButton>
                  </Box>
                </Box>
              ))}
            </Box>
            <Button
              variant="outlined"
              size="small"
              sx={styles.addSecretButton}
              onClick={handleAddSecret}
            >
              + Add Secret
            </Button>
          </Card>

          {/* Files */}
          <Card sx={styles.card}>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }}>
              <Typography sx={styles.cardTitle}>Files</Typography>
            </Box>
            <Typography sx={{ fontSize: '13px', color: 'text.secondary', marginBottom: '12px' }}>
              Files that will be available in the Docker container (e.g., Gemfile, script.rb, package.json)
            </Typography>
            <Box sx={styles.filesList}>
              {tool.files.map((file, index) => (
                <Box
                  key={index}
                  sx={{
                    ...styles.fileItem,
                    ...(selectedFileIndex === index ? styles.fileItemActive : {}),
                  }}
                  onClick={() => setSelectedFileIndex(index)}
                >
                  <Typography sx={styles.fileName}>📄 {file.name}</Typography>
                  <IconButton
                    size="small"
                    onClick={(e) => {
                      e.stopPropagation();
                      handleRemoveFile(index);
                    }}
                    sx={{ color: 'error.main' }}
                  >
                    ✕
                  </IconButton>
                </Box>
              ))}
            </Box>
            <Button
              variant="outlined"
              size="small"
              sx={styles.addSecretButton}
              onClick={handleAddFile}
            >
              + Add File
            </Button>

            {selectedFileIndex !== null && tool.files[selectedFileIndex] && (
              <Box sx={styles.fileEditor}>
                <Box sx={styles.fileEditorHeader}>
                  <Typography sx={styles.fileEditorTitle}>
                    {tool.files[selectedFileIndex].name}
                  </Typography>
                  <IconButton
                    size="small"
                    onClick={() => setSelectedFileIndex(null)}
                    sx={{ color: 'text.secondary' }}
                  >
                    ✕
                  </IconButton>
                </Box>
                <TextField
                  fullWidth
                  multiline
                  rows={12}
                  value={tool.files[selectedFileIndex].content}
                  onChange={(e) => handleUpdateFile(selectedFileIndex, { content: e.target.value })}
                  placeholder="File content..."
                  sx={styles.fileEditorContent}
                />
              </Box>
            )}
          </Card>
        </Box>

        {/* Terminal/Test Session */}
        <Box sx={styles.terminalContainer}>
          <Box sx={styles.terminalHeader}>
            <Typography sx={styles.terminalTitle}>
              <span style={{ color: selectedLanguage?.value === 'ruby' ? '#CC342D' : '#4785FF' }}>●</span>
              Test Session
            </Typography>
            {isTesting && (
              <Button
                size="small"
                variant="outlined"
                color="error"
                onClick={() => setIsTesting(false)}
                sx={{ textTransform: 'none', fontSize: '12px' }}
              >
                Stop Session
              </Button>
            )}
          </Box>

          {isTesting ? (
            <Box sx={styles.terminalContent}>
              <Box sx={styles.fileTree}>
                <Typography sx={styles.fileTreeHeader}>Files</Typography>
                {tool.files.map((file, index) => (
                  <Box
                    key={index}
                    sx={{
                      ...styles.fileItem,
                      ...(selectedFileForView === file.name ? styles.fileItemActive : {}),
                    }}
                    onClick={() => setSelectedFileForView(file.name)}
                  >
                    📄 {file.name}
                  </Box>
                ))}
                {tool.files.length === 0 && (
                  <Typography sx={{ fontSize: '12px', color: 'text.disabled', padding: '8px' }}>
                    No files added yet
                  </Typography>
                )}
              </Box>
              <Box sx={styles.terminalArea}>
                {/* In real app, this would be an iframe to ttyd */}
                <Box sx={styles.terminalPlaceholder}>
                  <Typography sx={styles.placeholderIcon}>💻</Typography>
                  <Typography sx={styles.placeholderText}>
                    Interactive terminal session
                  </Typography>
                  <Typography sx={{ fontSize: '12px', color: 'text.disabled', textAlign: 'center' }}>
                    Files are available in the workspace. Run your command to test the tool.
                  </Typography>
                </Box>
              </Box>
            </Box>
          ) : (
            <Box sx={styles.terminalPlaceholder}>
              <Typography sx={styles.placeholderIcon}>🧪</Typography>
              <Typography sx={styles.placeholderText}>
                Click "Test Tool" to start an interactive session
              </Typography>
              <Typography sx={{ fontSize: '12px', color: 'text.disabled', textAlign: 'center' }}>
                You'll be able to edit files, run commands, and test your tool configuration
              </Typography>
            </Box>
          )}
        </Box>
      </Box>

      <Box sx={styles.actions}>
        <Button
          variant="outlined"
          sx={styles.testButton}
          onClick={handleTest}
          disabled={!tool.name || !tool.command}
        >
          Test Tool
        </Button>
        <Button
          variant="contained"
          sx={styles.saveButton}
          onClick={handleSave}
          disabled={!tool.name || !tool.command}
        >
          Save Tool
        </Button>
      </Box>
    </Box>
  );
};

export default ToolConfigPanel;
