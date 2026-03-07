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

import { ConfigItemValueField } from './ConfigItemValueField';

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

  const [headersList, setHeadersList] = useState<{ key: string; value: string }[]>([]);
  const [envList, setEnvList] = useState<{ key: string; value: string }[]>([]);
  const [serverError, setServerError] = useState<string | null>(null);

  const {
    control,
    handleSubmit,
    reset,
    setValue,
    watch,
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
      command: '',
      env: {},
      description: '',
      enabled: true,
    },
  });

  const transport = watch('transport');
  const isStdio = transport === 'stdio';

  useEffect(() => {
    if (editServer) {
      const headers = editServer.headers ?? {};
      const headerList = Object.entries(headers).map(([key, value]) => ({ key, value: String(value) }));
      setHeadersList(headerList);

      const env = editServer.env ?? {};
      const envEntries = Object.entries(env).map(([key, value]) => ({ key, value: String(value) }));
      setEnvList(envEntries);

      reset({
        name: editServer.name,
        displayName: editServer.displayName,
        url: editServer.url ?? '',
        transport: editServer.transport,
        headers: headers,
        command: editServer.command ?? '',
        env: env,
        description: editServer.description ?? '',
        enabled: editServer.enabled,
      });
    } else {
      setHeadersList([]);
      setEnvList([]);
      reset({
        name: '',
        displayName: '',
        url: '',
        transport: 'http',
        headers: {},
        command: '',
        env: {},
        description: '',
        enabled: true,
      });
    }
    setServerError(null);
  }, [editServer, reset, open]);

  useEffect(() => {
    const headersObj: Record<string, string> = {};
    headersList.forEach(({ key, value }) => {
      if (key.trim()) {
        headersObj[key.trim()] = value;
      }
    });
    setValue('headers', headersObj);
  }, [headersList, setValue]);

  useEffect(() => {
    const envObj: Record<string, string> = {};
    envList.forEach(({ key, value }) => {
      if (key.trim()) {
        envObj[key.trim()] = value;
      }
    });
    setValue('env', envObj);
  }, [envList, setValue]);

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

  const handleAddEnv = () => {
    setEnvList([...envList, { key: '', value: '' }]);
  };

  const handleRemoveEnv = (index: number) => {
    const newList = [...envList];
    newList.splice(index, 1);
    setEnvList(newList);
  };

  const handleEnvChange = (index: number, field: 'key' | 'value', value: string) => {
    const newList = [...envList];
    newList[index][field] = value;
    setEnvList(newList);
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
      command: 'command',
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
          await updateProject({ projectId: projectId!, id: editServer.id, body: data }).unwrap();
        } else {
          await updateCompany({ id: editServer.id, body: data }).unwrap();
        }
      } else {
        if (isProjectContext) {
          await createProject({ projectId: projectId!, body: data }).unwrap();
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
                placeholder="playwright"
                error={!!errors.name}
                helperText={errors.name?.message ?? 'Lowercase identifier (e.g., playwright, context7)'}
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
                placeholder="Playwright Browser"
                error={!!errors.displayName}
                helperText={errors.displayName?.message}
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
                  <MenuItem value="http">HTTP (Streamable HTTP)</MenuItem>
                  <MenuItem value="sse">SSE (Server-Sent Events)</MenuItem>
                  <MenuItem value="stdio">Stdio (Local Process)</MenuItem>
                </Select>
                {errors.transport && <FormHelperText>{errors.transport.message}</FormHelperText>}
              </FormControl>
            )}
          />

          {!isStdio && (
            <>
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
                      <ConfigItemValueField
                        value={header.value}
                        onChange={(val) => handleHeaderChange(index, 'value', val)}
                        placeholder="Bearer token"
                      />
                      <IconButton size="small" color="error" onClick={() => handleRemoveHeader(index)}>
                        <DeleteIcon fontSize="small" />
                      </IconButton>
                    </Box>
                  ))}
                </Box>
              </Box>
            </>
          )}

          {isStdio && (
            <>
              <Controller
                name="command"
                control={control}
                render={({ field }) => (
                  <TextField
                    {...field}
                    label="Command"
                    placeholder="npx @automattic/mcp-wordpress-remote"
                    error={!!errors.command}
                    helperText={
                      errors.command?.message ?? 'Full command to run (e.g., npx @playwright/mcp --no-sandbox)'
                    }
                    fullWidth
                    sx={{ '& input': { fontFamily: 'monospace' } }}
                  />
                )}
              />

              <Box>
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 1 }}>
                  <Typography variant="subtitle2" color="text.secondary">
                    Environment Variables
                  </Typography>
                  <Button startIcon={<AddIcon />} size="small" onClick={handleAddEnv}>
                    Add Variable
                  </Button>
                </Box>

                {envList.length === 0 && (
                  <Typography variant="body2" color="text.disabled" sx={{ fontStyle: 'italic', mb: 1 }}>
                    No environment variables configured
                  </Typography>
                )}

                <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
                  {envList.map((envVar, index) => (
                    <Box key={index} sx={{ display: 'flex', gap: 1, alignItems: 'center' }}>
                      <TextField
                        label="Key"
                        size="small"
                        value={envVar.key}
                        onChange={(e) => handleEnvChange(index, 'key', e.target.value)}
                        placeholder="WP_API_URL"
                        fullWidth
                        sx={{ '& input': { fontFamily: 'monospace' } }}
                      />
                      <ConfigItemValueField
                        value={envVar.value}
                        onChange={(val) => handleEnvChange(index, 'value', val)}
                        placeholder="https://example.com"
                      />
                      <IconButton size="small" color="error" onClick={() => handleRemoveEnv(index)}>
                        <DeleteIcon fontSize="small" />
                      </IconButton>
                    </Box>
                  ))}
                </Box>
              </Box>
            </>
          )}

          <Controller
            name="description"
            control={control}
            render={({ field }) => (
              <TextField
                {...field}
                label="Description"
                placeholder={
                  isStdio ? 'Browser automation via Playwright...' : 'Provides documentation lookup capabilities...'
                }
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
