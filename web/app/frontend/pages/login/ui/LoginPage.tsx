import { zodResolver } from '@hookform/resolvers/zod';
import { Box, Button, Stack, SxProps, TextField, Typography } from '@mui/material';
import { useSearch } from '@tanstack/react-router';
import { useSnackbar } from 'notistack';
import { useEffect, useRef } from 'react';
import { FormProvider, useForm } from 'react-hook-form';

import { setErrorsToForm } from 'shared/api';
import { Logo } from 'shared/ui';

import { useLoginMutation } from '../api/loginApi';
import { LoginFormData, loginSchema } from '../lib/schema';

import { GoogleLoginButton } from './GoogleLoginButton';

const styles = {
  root: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: '100vh',
    backgroundColor: 'background.base',
    padding: '32px',
  },
  form: {
    width: '100%',
    maxWidth: '420px',
    padding: '24px',
    borderRadius: '8px',
    border: '1px solid',
    borderColor: 'border.defaultAlt',
    backgroundColor: 'background.surface',
  },
  logo: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: '32px',
  },
  title: {
    color: 'text.primaryAlt',
    marginBottom: '8px',
    textAlign: 'center',
    fontFamily: '"Inter", sans-serif',
    fontSize: '24px',
    fontWeight: 600,
    lineHeight: '32px',
  },
  subtitle: {
    color: 'text.secondaryAlt',
    fontFamily: '"Inter", sans-serif',
    fontSize: '14px',
    fontWeight: 400,
    lineHeight: '24px',
    marginBottom: '24px',
    textAlign: 'center',
  },
  fieldContainer: {
    display: 'flex',
    flexDirection: 'column',
    gap: '8px',
  },
  fieldLabel: {
    color: 'text.secondaryAlt',
    fontFamily: '"Inter", sans-serif',
    fontSize: '12px',
    fontWeight: 500,
    lineHeight: '24px',
  },
  textField: {
    '& .MuiOutlinedInput-root': {
      backgroundColor: 'background.base',
      borderRadius: '6px',
      '& fieldset': {
        borderColor: 'border.defaultAlt',
      },
      '&:hover fieldset': {
        borderColor: 'border.defaultAlt',
      },
      '&.Mui-focused fieldset': {
        borderColor: 'primary.main',
        borderWidth: '2px',
      },
    },
    '& .MuiOutlinedInput-input': {
      color: 'text.primaryAlt',
      fontFamily: '"Inter", sans-serif',
      fontSize: '14px',
      padding: '12px 16px',
      '&::placeholder': {
        color: 'text.muted',
      },
    },
    '& .MuiFormHelperText-root': {
      color: 'text.muted',
      fontFamily: '"Inter", sans-serif',
      fontSize: '12px',
      marginTop: '4px',
    },
  },
  button: {
    marginTop: '24px',
    padding: '12px 24px',
    borderRadius: '6px',
    backgroundColor: 'primary.main',
    color: '#FFFFFF',
    textTransform: 'none',
    fontFamily: '"Inter", sans-serif',
    fontSize: '14px',
    fontWeight: 500,
    lineHeight: '24px',
    '&:hover': {
      backgroundColor: 'primary.dark',
    },
    '&:disabled': {
      backgroundColor: 'text.muted',
      color: 'text.secondaryAlt',
    },
  },
  divider: {
    display: 'flex',
    alignItems: 'center',
    marginTop: '24px',
    marginBottom: '24px',
    color: 'text.muted',
    fontSize: '12px',
    fontWeight: 400,
    fontFamily: '"Inter", sans-serif',
    '&::before, &::after': {
      content: '""',
      flex: 1,
      borderBottom: '1px solid',
      borderColor: 'border.defaultAlt',
    },
    '&::before': {
      marginRight: '16px',
    },
    '&::after': {
      marginLeft: '16px',
    },
  },
  footer: {
    marginTop: '24px',
    textAlign: 'center',
    color: 'text.muted',
    fontFamily: '"Inter", sans-serif',
    fontSize: '12px',
    fontWeight: 400,
    lineHeight: '24px',
  },
} satisfies Record<string, SxProps>;

const LoginPage = () => {
  const methods = useForm<LoginFormData>({
    resolver: zodResolver(loginSchema),
    defaultValues: {
      email: '',
      password: '',
    },
  });

  const [login, { isLoading }] = useLoginMutation();
  const { enqueueSnackbar } = useSnackbar();
  const searchParams = useSearch({ from: '/login' }) as { error?: string };
  const errorShownRef = useRef(false);

  // Show error messages from OAuth redirect (only once)
  useEffect(() => {
    if (searchParams.error && !errorShownRef.current) {
      const errorMessages: Record<string, string> = {
        pending_approval: 'Your account is pending approval. Please contact your company administrator.',
        oauth_failed: 'Failed to authenticate with Google. Please try again.',
        oauth_error: 'An error occurred during authentication. Please try again.',
      };

      const message = errorMessages[searchParams.error] || 'Authentication failed. Please try again.';
      enqueueSnackbar(message, { variant: 'error' });
      errorShownRef.current = true;
    }
  }, [searchParams.error, enqueueSnackbar]);

  const onSubmit = async (data: LoginFormData) => {
    try {
      await login(data).unwrap();
      enqueueSnackbar('Welcome back!', { variant: 'success' });
      window.location.href = '/';
    } catch (error: unknown) {
      const message = setErrorsToForm(error, methods.setError) || 'Invalid email or password';
      enqueueSnackbar(message, { variant: 'error' });
    }
  };

  return (
    <Box sx={styles.root}>
      <Box sx={styles.form}>
        <Box sx={styles.logo}>
          <Logo width={120} colorScheme="dark" />
        </Box>

        <GoogleLoginButton />

        <Box sx={styles.divider}>OR</Box>

        <Typography sx={styles.subtitle}>Enter your credentials to access your workspace</Typography>

        <FormProvider {...methods}>
          <form onSubmit={methods.handleSubmit(onSubmit)}>
            <Stack spacing={3}>
              <Box sx={styles.fieldContainer}>
                <Typography sx={styles.fieldLabel}>Email</Typography>
                <TextField
                  {...methods.register('email')}
                  fullWidth
                  placeholder="you@company.com"
                  error={!!methods.formState.errors.email}
                  helperText={methods.formState.errors.email?.message}
                  autoComplete="username"
                  sx={styles.textField}
                />
              </Box>
              <Box sx={styles.fieldContainer}>
                <Typography sx={styles.fieldLabel}>Password</Typography>
                <TextField
                  {...methods.register('password')}
                  type="password"
                  fullWidth
                  placeholder="••••••••"
                  error={!!methods.formState.errors.password}
                  helperText={methods.formState.errors.password?.message}
                  autoComplete="current-password"
                  sx={styles.textField}
                />
              </Box>
              <Button type="submit" variant="contained" size="large" fullWidth disabled={isLoading} sx={styles.button}>
                {isLoading ? 'Signing in...' : 'Sign in'}
              </Button>
            </Stack>
          </form>
        </FormProvider>

        <Typography sx={styles.footer}>AI Agent Orchestration Platform</Typography>
      </Box>
    </Box>
  );
};

export default LoginPage;
