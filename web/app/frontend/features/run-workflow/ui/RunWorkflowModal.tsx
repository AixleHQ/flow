import {
  Box,
  Button,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  FormControl,
  FormControlLabel,
  InputLabel,
  MenuItem,
  Select,
  Switch,
  TextField,
  Typography,
} from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useSnackbar } from 'notistack';
import { useState } from 'react';

interface IWorkflowParameter {
  name: string;
  type: 'string' | 'number' | 'boolean';
  description?: string;
  defaultValue?: string | number | boolean;
  required: boolean;
}

interface IWorkflow {
  id: string;
  name: string;
  description?: string;
  parameters?: IWorkflowParameter[];
}

interface RunWorkflowModalProps {
  open: boolean;
  workflow: IWorkflow | null;
  onClose: () => void;
  onRun: (params: Record<string, any>) => void;
}

const styles = {
  dialog: {
    '& .MuiDialog-paper': {
      backgroundColor: 'background.paper',
      borderRadius: '12px',
      maxWidth: '600px',
      width: '100%',
    },
  },
  title: {
    fontSize: '20px',
    fontWeight: 600,
    color: 'text.primary',
    padding: '24px 24px 8px',
  },
  description: {
    fontSize: '14px',
    color: 'text.secondary',
    padding: '0 24px 16px',
  },
  content: {
    padding: '24px',
  },
  section: {
    marginBottom: '24px',
  },
  sectionTitle: {
    fontSize: '14px',
    fontWeight: 600,
    color: 'text.primary',
    marginBottom: '12px',
  },
  formField: {
    marginBottom: '16px',
  },
  label: {
    fontSize: '13px',
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
  switchLabel: {
    fontSize: '13px',
    color: 'text.primary',
  },
  actions: {
    padding: '16px 24px',
    borderTop: '1px solid',
    borderColor: 'divider',
  },
  cancelButton: {
    textTransform: 'none',
  },
  runButton: {
    textTransform: 'none',
    minWidth: '120px',
  },
  emptyState: {
    textAlign: 'center',
    padding: '32px',
  },
  emptyIcon: {
    fontSize: '48px',
    marginBottom: '16px',
  },
  emptyText: {
    fontSize: '14px',
    color: 'text.secondary',
  },
} satisfies Record<string, SxProps<Theme>>;

const RunWorkflowModal = ({ open, workflow, onClose, onRun }: RunWorkflowModalProps) => {
  const { enqueueSnackbar } = useSnackbar();
  const [params, setParams] = useState<Record<string, any>>({});
  const [autoStart, setAutoStart] = useState(true);

  const handleParamChange = (name: string, value: any) => {
    setParams((prev) => ({ ...prev, [name]: value }));
  };

  const handleRun = () => {
    if (!workflow) return;

    // Validate required parameters
    const requiredParams = workflow.parameters?.filter((p) => p.required) || [];
    const missingParams = requiredParams.filter((p) => !params[p.name] && params[p.name] !== false);

    if (missingParams.length > 0) {
      enqueueSnackbar(`Please fill in required parameters: ${missingParams.map((p) => p.name).join(', ')}`, {
        variant: 'warning',
      });
      return;
    }

    onRun({
      ...params,
      autoStart,
    });
    handleClose();
  };

  const handleClose = () => {
    setParams({});
    setAutoStart(true);
    onClose();
  };

  if (!workflow) {
    return (
      <Dialog open={open} onClose={handleClose} sx={styles.dialog}>
        <DialogContent>
          <Box sx={styles.emptyState}>
            <Typography sx={styles.emptyIcon}>⚠️</Typography>
            <Typography sx={styles.emptyText}>No workflow selected</Typography>
          </Box>
        </DialogContent>
        <DialogActions sx={styles.actions}>
          <Button onClick={handleClose} sx={styles.cancelButton}>
            Close
          </Button>
        </DialogActions>
      </Dialog>
    );
  }

  return (
    <Dialog open={open} onClose={handleClose} sx={styles.dialog}>
      <DialogTitle sx={styles.title}>Run Workflow</DialogTitle>
      {workflow.description && <Typography sx={styles.description}>{workflow.description}</Typography>}

      <DialogContent sx={styles.content}>
        {/* Workflow Parameters */}
        {workflow.parameters && workflow.parameters.length > 0 ? (
          <Box sx={styles.section}>
            <Typography sx={styles.sectionTitle}>Parameters</Typography>
            {workflow.parameters.map((param) => (
              <Box key={param.name} sx={styles.formField}>
                <Typography sx={styles.label}>
                  {param.name}
                  {param.required && <span style={{ color: 'error.main', marginLeft: '4px' }}>*</span>}
                  {param.description && (
                    <Typography sx={{ fontSize: '12px', color: 'text.disabled', marginTop: '4px' }}>
                      {param.description}
                    </Typography>
                  )}
                </Typography>
                {param.type === 'boolean' ? (
                  <FormControlLabel
                    control={
                      <Switch
                        checked={params[param.name] ?? param.defaultValue ?? false}
                        onChange={(e) => handleParamChange(param.name, e.target.checked)}
                      />
                    }
                    label={params[param.name] ?? param.defaultValue ?? false ? 'Yes' : 'No'}
                    sx={styles.switchLabel}
                  />
                ) : param.type === 'number' ? (
                  <TextField
                    fullWidth
                    size="small"
                    type="number"
                    value={params[param.name] ?? param.defaultValue ?? ''}
                    onChange={(e) => handleParamChange(param.name, Number(e.target.value))}
                    placeholder={`Enter ${param.name}`}
                    sx={styles.input}
                  />
                ) : (
                  <TextField
                    fullWidth
                    size="small"
                    value={params[param.name] ?? param.defaultValue ?? ''}
                    onChange={(e) => handleParamChange(param.name, e.target.value)}
                    placeholder={`Enter ${param.name}`}
                    sx={styles.input}
                  />
                )}
              </Box>
            ))}
          </Box>
        ) : (
          <Box sx={styles.emptyState}>
            <Typography sx={styles.emptyIcon}>🚀</Typography>
            <Typography sx={styles.emptyText}>This workflow has no parameters</Typography>
          </Box>
        )}

        {/* Options */}
        <Box sx={styles.section}>
          <Typography sx={styles.sectionTitle}>Options</Typography>
          <FormControlLabel
            control={<Switch checked={autoStart} onChange={(e) => setAutoStart(e.target.checked)} />}
            label="Start immediately after creation"
            sx={styles.switchLabel}
          />
        </Box>
      </DialogContent>

      <DialogActions sx={styles.actions}>
        <Button onClick={handleClose} sx={styles.cancelButton}>
          Cancel
        </Button>
        <Button variant="contained" onClick={handleRun} sx={styles.runButton}>
          Run Workflow
        </Button>
      </DialogActions>
    </Dialog>
  );
};

export default RunWorkflowModal;
