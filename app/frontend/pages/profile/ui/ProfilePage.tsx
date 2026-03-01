import { zodResolver } from '@hookform/resolvers/zod';
import LockIcon from '@mui/icons-material/Lock';
import {
  Box,
  Button,
  Card,
  CardContent,
  Chip,
  CircularProgress,
  FormControl,
  FormHelperText,
  InputLabel,
  MenuItem,
  Select,
  TextField,
  Tooltip,
  Typography,
} from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useSnackbar } from 'notistack';
import { useEffect } from 'react';
import { Controller, useForm } from 'react-hook-form';

import {
  LANGUAGE_OPTIONS,
  useGetCurrentUserQuery,
  useUpdateCurrentUserMutation,
  type AgentLanguage,
  type UserRole,
} from 'entities/user';
import { AgentCredentialsSection } from 'features/agent-credentials';

import { profileSchema, type IProfileFormData } from '../lib/profileSchema';

import { DefaultAgentSelector } from './DefaultAgentSelector';

const styles = {
  root: {
    minHeight: '100vh',
    backgroundColor: 'background.default',
    padding: '32px',
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
  },
  container: {
    width: '100%',
    maxWidth: '600px',
  },
  title: {
    fontSize: '32px',
    fontWeight: 600,
    color: 'text.primary',
    marginBottom: '24px',
  },
  card: {
    backgroundColor: 'background.paper',
  },
  fieldContainer: {
    marginBottom: '24px',
  },
  fieldLabel: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    marginBottom: '8px',
  },
  label: {
    fontSize: '14px',
    fontWeight: 500,
    color: 'text.secondary',
  },
  lockIcon: {
    fontSize: '16px',
    color: 'text.disabled',
  },
  readOnlyValue: {
    fontSize: '16px',
    color: 'text.primary',
    padding: '8px 0',
  },
  helperText: {
    fontSize: '12px',
    color: 'text.disabled',
    marginTop: '4px',
  },
  roleContainer: {
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
    padding: '8px 0',
  },
  buttonContainer: {
    marginTop: '8px',
  },
} satisfies Record<string, SxProps<Theme>>;

const getRoleBadgeColor = (role: UserRole): 'secondary' | 'primary' | 'default' => {
  switch (role) {
    case 'super_admin':
      return 'secondary'; // purple
    case 'admin':
      return 'primary'; // blue
    case 'employee':
    default:
      return 'default'; // gray
  }
};

const getRoleDisplayName = (role: UserRole): string => {
  switch (role) {
    case 'super_admin':
      return 'Super Admin';
    case 'admin':
      return 'Admin';
    case 'employee':
    default:
      return 'Employee';
  }
};

const ProfilePage: React.FC = () => {
  const { enqueueSnackbar } = useSnackbar();
  const { data: currentUser, isLoading: isUserLoading } = useGetCurrentUserQuery();
  const [updateUser, { isLoading: isUpdating }] = useUpdateCurrentUserMutation();

  const {
    control,
    handleSubmit,
    reset,
    formState: { errors, isDirty, isValid },
  } = useForm<IProfileFormData>({
    resolver: zodResolver(profileSchema),
    defaultValues: {
      name: '',
      preferredAgentLanguage: undefined,
    },
    mode: 'onChange',
  });

  // Reset form when user data loads
  useEffect(() => {
    if (currentUser) {
      reset({
        name: currentUser.name,
        preferredAgentLanguage: currentUser.preferredAgentLanguage as AgentLanguage,
      });
    }
  }, [currentUser, reset]);

  const onSubmit = async (data: IProfileFormData) => {
    try {
      await updateUser({
        currentUser: {
          name: data.name,
          preferredAgentLanguage: data.preferredAgentLanguage,
        },
      }).unwrap();
      enqueueSnackbar('Profile updated successfully', { variant: 'success' });
      reset(data);
    } catch {
      enqueueSnackbar('Failed to update profile. Please try again.', { variant: 'error' });
    }
  };

  if (isUserLoading || !currentUser) {
    return (
      <Box sx={styles.root}>
        <CircularProgress />
      </Box>
    );
  }

  const companyDisplayName = currentUser.company?.name ?? 'Platform Administrator';

  return (
    <Box sx={styles.root}>
      <Box sx={styles.container}>
        <Typography sx={styles.title}>My Profile</Typography>

        <Card sx={styles.card}>
          <CardContent>
            <form onSubmit={handleSubmit(onSubmit)}>
              {/* Email (Read-only) */}
              <Box sx={styles.fieldContainer}>
                <Box sx={styles.fieldLabel}>
                  <Typography sx={styles.label}>Email</Typography>
                  <Tooltip title="Email is managed by Google OAuth and cannot be changed">
                    <LockIcon sx={styles.lockIcon} />
                  </Tooltip>
                </Box>
                <Typography sx={styles.readOnlyValue}>{currentUser.email}</Typography>
                <Typography sx={styles.helperText}>Email is managed by Google OAuth and cannot be changed</Typography>
              </Box>

              {/* Display Name (Editable) */}
              <Box sx={styles.fieldContainer}>
                <Controller
                  name="name"
                  control={control}
                  render={({ field }) => (
                    <TextField
                      {...field}
                      label="Display Name"
                      variant="outlined"
                      fullWidth
                      error={!!errors.name}
                      helperText={errors.name?.message}
                      disabled={isUpdating}
                    />
                  )}
                />
              </Box>

              {/* Preferred Agent Language (Editable) */}
              <Box sx={styles.fieldContainer}>
                <Controller
                  name="preferredAgentLanguage"
                  control={control}
                  render={({ field }) => (
                    <FormControl fullWidth error={!!errors.preferredAgentLanguage}>
                      <InputLabel>Agent Language</InputLabel>
                      <Select {...field} label="Agent Language" disabled={isUpdating}>
                        {LANGUAGE_OPTIONS.map((option) => (
                          <MenuItem key={option.value} value={option.value}>
                            {option.label}
                          </MenuItem>
                        ))}
                      </Select>
                      <FormHelperText>
                        {errors.preferredAgentLanguage?.message ??
                          'Language AI agents will use to communicate with you'}
                      </FormHelperText>
                    </FormControl>
                  )}
                />
              </Box>

              {/* Company (Read-only) */}
              <Box sx={styles.fieldContainer}>
                <Box sx={styles.fieldLabel}>
                  <Typography sx={styles.label}>Company</Typography>
                  <Tooltip title="Company assignment is managed by administrators">
                    <LockIcon sx={styles.lockIcon} />
                  </Tooltip>
                </Box>
                <Typography sx={styles.readOnlyValue}>{companyDisplayName}</Typography>
              </Box>

              {/* Role (Read-only) */}
              <Box sx={styles.fieldContainer}>
                <Box sx={styles.fieldLabel}>
                  <Typography sx={styles.label}>Role</Typography>
                </Box>
                <Box sx={styles.roleContainer}>
                  <Chip
                    label={getRoleDisplayName(currentUser.role)}
                    color={getRoleBadgeColor(currentUser.role)}
                    size="small"
                  />
                </Box>
              </Box>

              {/* Save Button */}
              <Box sx={styles.buttonContainer}>
                <Button
                  type="submit"
                  variant="contained"
                  color="primary"
                  disabled={!isDirty || !isValid || isUpdating}
                  startIcon={isUpdating ? <CircularProgress size={20} color="inherit" /> : undefined}
                >
                  {isUpdating ? 'Saving...' : 'Save Changes'}
                </Button>
              </Box>
            </form>
          </CardContent>
        </Card>

        <DefaultAgentSelector />
        <AgentCredentialsSection />
      </Box>
    </Box>
  );
};

export default ProfilePage;
