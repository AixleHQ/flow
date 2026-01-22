import { zodResolver } from '@hookform/resolvers/zod';
import { Box, Button, Stack, TextField, Typography } from '@mui/material';
import { useSnackbar } from 'notistack';
import { FormProvider, useForm } from 'react-hook-form';

import { setErrorsToForm } from 'shared/api';
import { Logo } from 'shared/ui';

import { useLoginMutation } from '../api/loginApi';
import { LoginFormData, loginSchema } from '../lib/schema';

// UX Design Specification colors
const colors = {
  background: {
    base: '#09090B', // Page background
    surface: '#18181B', // Cards, panels
    elevated: '#27272A', // Hover, selected
  },
  border: {
    default: '#3F3F46', // Borders, dividers
  },
  text: {
    primary: '#D4D4D8', // Main text
    secondary: '#A1A1AA', // Secondary text
    muted: '#52525B', // Disabled, hints
  },
  accent: {
    blue: '#3B82F6', // Primary actions, links
  },
} as const;

const styles = {
  root: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: '100vh',
    backgroundColor: colors.background.base,
    padding: '32px',
  },
  form: {
    width: '100%',
    maxWidth: '420px',
    padding: '24px',
    borderRadius: '8px',
    border: `1px solid ${colors.border.default}`,
    backgroundColor: colors.background.surface,
  },
  logo: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: '32px',
  },
  title: {
    color: colors.text.primary,
    marginBottom: '8px',
    textAlign: 'center',
    fontFamily: '"Inter", sans-serif',
    fontSize: '24px',
    fontWeight: 600,
    lineHeight: '32px',
  },
  subtitle: {
    color: colors.text.secondary,
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
    color: colors.text.secondary,
    fontFamily: '"Inter", sans-serif',
    fontSize: '12px',
    fontWeight: 500,
    lineHeight: '24px',
  },
  textField: {
    '& .MuiOutlinedInput-root': {
      backgroundColor: colors.background.base,
      borderRadius: '6px',
      '& fieldset': {
        borderColor: colors.border.default,
      },
      '&:hover fieldset': {
        borderColor: colors.border.default,
      },
      '&.Mui-focused fieldset': {
        borderColor: colors.accent.blue,
        borderWidth: '2px',
      },
    },
    '& .MuiOutlinedInput-input': {
      color: colors.text.primary,
      fontFamily: '"Inter", sans-serif',
      fontSize: '14px',
      padding: '12px 16px',
      '&::placeholder': {
        color: colors.text.muted,
      },
    },
    '& .MuiFormHelperText-root': {
      color: colors.text.muted,
      fontFamily: '"Inter", sans-serif',
      fontSize: '12px',
      marginTop: '4px',
    },
  },
  button: {
    marginTop: '24px',
    padding: '12px 24px',
    borderRadius: '6px',
    backgroundColor: colors.accent.blue,
    color: '#FFFFFF',
    textTransform: 'none',
    fontFamily: '"Inter", sans-serif',
    fontSize: '14px',
    fontWeight: 500,
    lineHeight: '24px',
    '&:hover': {
      backgroundColor: '#2563EB', // accent.blue dark
    },
    '&:disabled': {
      backgroundColor: colors.text.muted,
      color: colors.text.secondary,
    },
  },
  footer: {
    marginTop: '24px',
    textAlign: 'center',
    color: colors.text.muted,
    fontFamily: '"Inter", sans-serif',
    fontSize: '12px',
    fontWeight: 400,
    lineHeight: '24px',
  },
} as const;

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
          <Logo width={120} />
        </Box>

        <Typography sx={styles.title}>
          Sign in
        </Typography>
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
