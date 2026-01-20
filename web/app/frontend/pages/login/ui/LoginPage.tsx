import { zodResolver } from '@hookform/resolvers/zod';
import { Box, Button, Stack, TextField, Typography } from '@mui/material';
import { useSnackbar } from 'notistack';
import { FormProvider, useForm } from 'react-hook-form';

import { setErrorsToForm } from 'shared/api';

import { useLoginMutation } from '../api/loginApi';
import { LoginFormData, loginSchema } from '../lib/schema';

const styles = {
  root: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: '100vh',
    background: 'linear-gradient(135deg, #1a1b26 0%, #24283b 50%, #1a1b26 100%)',
    position: 'relative',
    overflow: 'hidden',
    '&::before': {
      content: '""',
      position: 'absolute',
      top: '-50%',
      left: '-50%',
      width: '200%',
      height: '200%',
      background:
        'radial-gradient(circle at 30% 30%, rgba(71, 133, 255, 0.08) 0%, transparent 50%), radial-gradient(circle at 70% 70%, rgba(187, 154, 247, 0.06) 0%, transparent 50%)',
      animation: 'pulse 15s ease-in-out infinite',
    },
    '@keyframes pulse': {
      '0%, 100%': { opacity: 1 },
      '50%': { opacity: 0.7 },
    },
  },
  form: {
    width: '100%',
    maxWidth: '420px',
    padding: '48px 40px',
    borderRadius: '16px',
    border: '1px solid rgba(71, 133, 255, 0.2)',
    background: 'linear-gradient(180deg, rgba(36, 40, 59, 0.95) 0%, rgba(26, 27, 38, 0.98) 100%)',
    boxShadow: '0px 24px 48px rgba(0, 0, 0, 0.4), 0px 0px 1px rgba(71, 133, 255, 0.3)',
    backdropFilter: 'blur(20px)',
    position: 'relative',
    zIndex: 1,
  },
  logo: {
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: '32px',
  },
  logoIcon: {
    width: '48px',
    height: '48px',
    borderRadius: '12px',
    background: 'linear-gradient(135deg, #4785FF 0%, #bb9af7 100%)',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    marginRight: '12px',
    boxShadow: '0 4px 16px rgba(71, 133, 255, 0.3)',
  },
  logoText: {
    fontFamily: '"JetBrains Mono", monospace',
    fontSize: '28px',
    fontWeight: 700,
    background: 'linear-gradient(135deg, #ffffff 0%, #a9b1d6 100%)',
    WebkitBackgroundClip: 'text',
    WebkitTextFillColor: 'transparent',
    letterSpacing: '-0.5px',
  },
  title: {
    color: '#c0caf5',
    marginBottom: '8px',
    textAlign: 'center',
  },
  subtitle: {
    color: 'rgba(192, 202, 245, 0.6)',
    fontFamily: '"Inter", sans-serif',
    fontSize: '14px',
    fontWeight: 400,
    letterSpacing: '0.01em',
    marginBottom: '32px',
    textAlign: 'center',
  },
  fieldContainer: {
    display: 'flex',
    flexDirection: 'column',
    gap: '8px',
  },
  fieldLabel: {
    color: 'rgba(192, 202, 245, 0.8)',
    fontSize: '13px',
    fontWeight: 500,
    letterSpacing: '0.5px',
    textTransform: 'uppercase',
  },
  textField: {
    '& .MuiOutlinedInput-root': {
      backgroundColor: 'rgba(26, 27, 38, 0.6)',
      borderRadius: '8px',
      '& fieldset': {
        borderColor: 'rgba(71, 133, 255, 0.2)',
      },
      '&:hover fieldset': {
        borderColor: 'rgba(71, 133, 255, 0.4)',
      },
      '&.Mui-focused fieldset': {
        borderColor: '#4785FF',
        borderWidth: '1px',
      },
    },
    '& .MuiOutlinedInput-input': {
      color: '#c0caf5',
      padding: '14px 16px',
      '&::placeholder': {
        color: 'rgba(192, 202, 245, 0.4)',
      },
    },
  },
  button: {
    marginTop: '24px',
    padding: '14px 24px',
    borderRadius: '8px',
    background: 'linear-gradient(135deg, #4785FF 0%, #5a9cff 100%)',
    boxShadow: '0 4px 16px rgba(71, 133, 255, 0.3)',
    textTransform: 'none',
    fontSize: '15px',
    fontWeight: 600,
    letterSpacing: '0.3px',
    transition: 'all 0.2s ease',
    '&:hover': {
      background: 'linear-gradient(135deg, #5a9cff 0%, #4785FF 100%)',
      boxShadow: '0 6px 20px rgba(71, 133, 255, 0.4)',
      transform: 'translateY(-1px)',
    },
    '&:disabled': {
      background: 'rgba(71, 133, 255, 0.3)',
      color: 'rgba(255, 255, 255, 0.5)',
    },
  },
  footer: {
    marginTop: '24px',
    textAlign: 'center',
    color: 'rgba(192, 202, 245, 0.4)',
    fontSize: '12px',
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
          <Box sx={styles.logoIcon}>
            <Typography sx={{ color: '#fff', fontSize: '24px', fontWeight: 700 }}>P</Typography>
          </Box>
          <Typography sx={styles.logoText}>Palad</Typography>
        </Box>

        <Typography variant="displaySmall" sx={styles.title}>
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
