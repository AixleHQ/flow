import { zodResolver } from '@hookform/resolvers/zod';
import {
  Button,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  FormControl,
  FormHelperText,
  InputLabel,
  MenuItem,
  Select,
  Stack,
  TextField,
} from '@mui/material';
import { useSnackbar } from 'notistack';
import type { FC } from 'react';
import { FormProvider, useForm, Controller } from 'react-hook-form';

import { useGetCurrentUserQuery } from 'entities/user';
import { setErrorsToForm } from 'shared/api';

import { useCreateCompanyUserMutation } from '../api/companyUsersApi';
import { inviteUserSchema, type InviteUserFormData } from '../lib/inviteUserSchema';

interface InviteUserDialogProps {
  open: boolean;
  onClose: () => void;
}

const InviteUserDialog: FC<InviteUserDialogProps> = ({ open, onClose }) => {
  const { data: currentUser } = useGetCurrentUserQuery();
  const [createUser, { isLoading }] = useCreateCompanyUserMutation();
  const { enqueueSnackbar } = useSnackbar();

  const emailDomain = currentUser?.company?.emailDomain;

  const methods = useForm<InviteUserFormData>({
    resolver: zodResolver(inviteUserSchema),
    defaultValues: {
      email: '',
      name: '',
      role: 'employee',
    },
  });

  const handleClose = () => {
    methods.reset();
    onClose();
  };

  const onSubmit = async (data: InviteUserFormData) => {
    try {
      await createUser(data).unwrap();
      enqueueSnackbar('User invited successfully', { variant: 'success' });
      handleClose();
    } catch (error: unknown) {
      const message = setErrorsToForm(error, methods.setError) || 'Failed to invite user';
      enqueueSnackbar(message, { variant: 'error' });
    }
  };

  return (
    <Dialog open={open} onClose={handleClose} maxWidth="sm" fullWidth>
      <DialogTitle>Invite User</DialogTitle>
      <FormProvider {...methods}>
        <form onSubmit={methods.handleSubmit(onSubmit)}>
          <DialogContent>
            <Stack spacing={3}>
              <TextField
                {...methods.register('email')}
                label="Email Address"
                placeholder={emailDomain ? `user@${emailDomain}` : 'user@company.com'}
                fullWidth
                error={!!methods.formState.errors.email}
                helperText={
                  methods.formState.errors.email?.message || (emailDomain ? `Email must end with @${emailDomain}` : '')
                }
                autoFocus
              />

              <TextField
                {...methods.register('name')}
                label="Full Name"
                placeholder="John Doe"
                fullWidth
                error={!!methods.formState.errors.name}
                helperText={methods.formState.errors.name?.message}
              />

              <Controller
                name="role"
                control={methods.control}
                render={({ field, fieldState }) => (
                  <FormControl fullWidth error={!!fieldState.error}>
                    <InputLabel id="role-label">Role</InputLabel>
                    <Select {...field} labelId="role-label" label="Role">
                      <MenuItem value="employee">Employee</MenuItem>
                      <MenuItem value="admin">Admin</MenuItem>
                    </Select>
                    {fieldState.error && <FormHelperText>{fieldState.error.message}</FormHelperText>}
                  </FormControl>
                )}
              />
            </Stack>
          </DialogContent>
          <DialogActions>
            <Button onClick={handleClose} disabled={isLoading}>
              Cancel
            </Button>
            <Button type="submit" variant="contained" disabled={isLoading}>
              {isLoading ? 'Inviting...' : 'Invite'}
            </Button>
          </DialogActions>
        </form>
      </FormProvider>
    </Dialog>
  );
};

export { InviteUserDialog };
