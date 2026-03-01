import { zodResolver } from '@hookform/resolvers/zod';
import AddIcon from '@mui/icons-material/Add';
import DeleteIcon from '@mui/icons-material/Delete';
import {
  Box,
  Button,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  FormControl,
  FormHelperText,
  IconButton,
  InputLabel,
  MenuItem,
  Select,
  Switch,
  TextField,
  FormControlLabel,
  Typography,
} from '@mui/material';
import { useEffect, useState, type FC } from 'react';
import { Controller, useForm } from 'react-hook-form';

import {
  useCreateMcpServerMutation,
  useUpdateMcpServerMutation,
  useCreateProjectMcpServerMutation,
  useUpdateProjectMcpServerMutation,
  type McpServer,
} from 'entities/mcp-server';

import { mcpServerSchema, type McpServerFormData } from '../lib/mcpServerSchema';

interface McpServerFormDialogProps {
  open: boolean;
  onClose: () => void;
  projectId?: number;
  editServer?: McpServer | null;
}

export const McpServerFormDialog: FC<McpServerFormDialogProps> = ({ open, onClose, projectId, editServer }) => {
  const isEdit = !!editServer;
  const isProjectContext = !!projectId;

  const [createCompany, { isLoading: isCreatingCompany }] = useCreateMcpServerMutation();
  const [updateCompany, { isLoading: isUpdatingCompany }] = useUpdateMcpServerMutation();
  const [createProject, { isLoading: isCreatingProject }] = useCreateProjectMcpServerMutation();
  const [updateProject, { isLoading: isUpdatingProject }] = useUpdateProjectMcpServerMutation();

  const isLoading = isCreatingCompany || isUpdatingCompany || isCreatingProject || isUpdatingProject;

  // Local state for headers editor
  const [headersList, setHeadersList] = useState<{ key: string; value: string }[]>([]);

  const [serverError, setServerError] = useState<string | null>(null);

  const {
    control,
    handleSubmit,
    reset,
    setValue,
    setError,
    formState: { errors },
  } = useForm<McpServerFormData>({
    resolver: zodResolver(mcpServerSchema),
    defaultValues: {
      name: '',
      displayName: '',
      url: '',
      transport: 'http',
      headers: {},
      description: '',
      enabled: true,
    },
  });

  useEffect(() => {
    if (editServer) {
      // Convert headers object to list for editor
      const headers = editServer.headers ?? {};
      const list = Object.entries(headers).map(([key, value]) => ({ key, value: String(value) }));
      setHeadersList(list);

      reset({
        name: editServer.name,
        displayName: editServer.displayName,
        url: editServer.url,
        transport: editServer.transport,
        headers: headers,
        description: editServer.description ?? '',
        enabled: editServer.enabled,
      });
    } else {
      setHeadersList([]);
      reset({
        name: '',
        displayName: '',
        url: '',
        transport: 'http',
        headers: {},
        description: '',
        enabled: true,
      });
    }
    setServerError(null);
  }, [editServer, reset, open]);

  // Update form value when headers list changes
  useEffect(() => {
    const headersObj: Record<string, string> = {};
    headersList.forEach(({ key, value }) => {
      if (key.trim()) {
        headersObj[key.trim()] = value;
      }
    });
    setValue('headers', headersObj);
  }, [headersList, setValue]);

  const handleAddHeader = () => {
    setHeadersList([...headersList, { key: '', value: '' }]);
  };

  const handleRemoveHeader = (index: number) => {
    const newList = [...headersList];
    newList.splice(index, 1);
    setHeadersList(newList);
  };

  const handleHeaderChange = (index: number, field: 'key' | 'value', value: string) => {
    const newList = [...headersList];
    newList[index][field] = value;
    setHeadersList(newList);
  };

  const applyServerErrors = (error: unknown) => {
    const data = (error as { data?: { errors?: Record<string, string[]> } })?.data;
    const fieldErrors = data?.errors;
    if (!fieldErrors) {
      setServerError('Failed to save MCP server');
      return;
    }

    const fieldMap: Record<string, keyof McpServerFormData> = {
      name: 'name',
      display_name: 'displayName',
      url: 'url',
      transport: 'transport',
    };

    let hasFieldError = false;
    for (const [serverField, messages] of Object.entries(fieldErrors)) {
      const formField = fieldMap[serverField];
      if (formField) {
        setError(formField, { message: messages.join(', ') });
        hasFieldError = true;
      }
    }

    if (!hasFieldError) {
      const allMessages = Object.values(fieldErrors).flat().join('; ');
      setServerError(allMessages);
    }
  };

  const onSubmit = async (data: McpServerFormData) => {
    setServerError(null);
    try {
      if (isEdit && editServer) {
        if (isProjectContext) {
          await updateProject({
            projectId: projectId!,
            id: editServer.id,
            body: data,
          }).unwrap();
        } else {
          await updateCompany({
            id: editServer.id,
            body: data,
          }).unwrap();
        }
      } else {
        if (isProjectContext) {
          await createProject({
            projectId: projectId!,
            body: data,
          }).unwrap();
        } else {
          await createCompany(data).unwrap();
        }
      }
      onClose();
    } catch (error) {
      applyServerErrors(error);
    }
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>{isEdit ? 'Edit MCP Server' : 'Add MCP Server'}</DialogTitle>
      <DialogContent>
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, mt: 1 }}>
          <Controller
            name="name"
            control={control}
            render={({ field }) => (
              <TextField
                {...field}
                label="Name"
                placeholder="context7"
                error={!!errors.name}
                helperText={errors.name?.message ?? 'Lowercase identifier (e.g., context7, tavily-search)'}
                disabled={isEdit}
                fullWidth
              />
            )}
          />

          <Controller
            name="displayName"
            control={control}
            render={({ field }) => (
              <TextField
                {...field}
                label="Display Name"
                placeholder="Context7"
                error={!!errors.displayName}
                helperText={errors.displayName?.message}
                fullWidth
              />
            )}
          />

          <Controller
            name="url"
            control={control}
            render={({ field }) => (
              <TextField
                {...field}
                label="URL"
                placeholder="https://mcp.example.com"
                error={!!errors.url}
                helperText={errors.url?.message ?? 'MCP server endpoint URL'}
                fullWidth
              />
            )}
          />

          <Controller
            name="transport"
            control={control}
            render={({ field }) => (
              <FormControl fullWidth error={!!errors.transport}>
                <InputLabel>Transport</InputLabel>
                <Select {...field} label="Transport">
                  <MenuItem value="http">HTTP</MenuItem>
                  <MenuItem value="sse">SSE (Server-Sent Events)</MenuItem>
                </Select>
                {errors.transport && <FormHelperText>{errors.transport.message}</FormHelperText>}
              </FormControl>
            )}
          />

          <Box>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 1 }}>
              <Typography variant="subtitle2" color="text.secondary">
                Headers
              </Typography>
              <Button startIcon={<AddIcon />} size="small" onClick={handleAddHeader}>
                Add Header
              </Button>
            </Box>

            {headersList.length === 0 && (
              <Typography variant="body2" color="text.disabled" sx={{ fontStyle: 'italic', mb: 1 }}>
                No headers configured
              </Typography>
            )}

            <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
              {headersList.map((header, index) => (
                <Box key={index} sx={{ display: 'flex', gap: 1, alignItems: 'center' }}>
                  <TextField
                    label="Key"
                    size="small"
                    value={header.key}
                    onChange={(e) => handleHeaderChange(index, 'key', e.target.value)}
                    placeholder="Authorization"
                    fullWidth
                  />
                  <TextField
                    label="Value"
                    size="small"
                    value={header.value}
                    onChange={(e) => handleHeaderChange(index, 'value', e.target.value)}
                    placeholder="Bearer token"
                    fullWidth
                  />
                  <IconButton size="small" color="error" onClick={() => handleRemoveHeader(index)}>
                    <DeleteIcon fontSize="small" />
                  </IconButton>
                </Box>
              ))}
            </Box>
          </Box>

          <Controller
            name="description"
            control={control}
            render={({ field }) => (
              <TextField
                {...field}
                label="Description"
                placeholder="Provides documentation lookup capabilities..."
                multiline
                rows={2}
                fullWidth
              />
            )}
          />

          <Controller
            name="enabled"
            control={control}
            render={({ field }) => (
              <FormControlLabel control={<Switch {...field} checked={field.value} />} label="Enabled" />
            )}
          />

          {serverError && (
            <Typography color="error" variant="body2">
              {serverError}
            </Typography>
          )}
        </Box>
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose} disabled={isLoading}>
          Cancel
        </Button>
        <Button variant="contained" onClick={handleSubmit(onSubmit)} disabled={isLoading}>
          {isEdit ? 'Save' : 'Create'}
        </Button>
      </DialogActions>
    </Dialog>
  );
};
