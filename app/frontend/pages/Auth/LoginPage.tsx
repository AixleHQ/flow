import { Head, router, useForm, usePage } from '@inertiajs/react';
import { Button, Center, Checkbox, Divider, Paper, PasswordInput, Stack, Text, TextInput, Title } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useEffect, useRef, useState } from 'react';
import { z } from 'zod';

import { loginPath, ssoDiscoveryPath } from 'shared/routes';
import { Logo, PageShell } from 'shared/ui';

import { GoogleLoginButton } from './GoogleLoginButton';
import classes from './LoginPage.module.css';
import { MicrosoftLoginButton } from './MicrosoftLoginButton';
import { PasswordlessOptions } from './PasswordlessOptions';

interface PageProps {
  error?: string;
  email?: string;
  /** Redirect providers this installation offers. Absent means Google only. */
  oauth_providers?: string[];
  passwordless_methods?: string[];
  [key: string]: unknown;
}

const ERROR_MESSAGES: Record<string, string> = {
  pending_approval: 'Your account is pending approval. Please contact your company administrator.',
  no_active_membership: 'You no longer have access to any workspace. Please contact your company administrator.',
  deactivated: 'Your account has been deactivated. Please contact your company administrator.',
  account_deleted: 'This account has been deleted. Please contact your company administrator.',
  oauth_failed: 'Failed to authenticate with Google. Please try again.',
  oauth_error: 'An error occurred during authentication. Please try again.',
  super_admin_password_only: 'Administrator accounts sign in with a password only.',
  link_required:
    'An account already exists for that address. Sign in the way you usually do, then add this method from your security settings.',
  no_workspace: 'No workspace matches that email address. Please contact your administrator.',
};

function NoWorkspaceScreen() {
  return (
    <Paper className={classes.formCard} p="xl" radius="md" w="100%" maw={420} shadow="0 8px 32px rgba(0, 0, 0, 0.4)">
      <Center mb={32}>
        <span className={classes.brand}>
          {/* No colorScheme override: pinning it to "dark" inverts the mark to
                  white, which disappears on the light-scheme login card. */}
          <Logo width={96} />
          <span className={classes.brandFlow}>Flow</span>
        </span>
      </Center>
      <Title order={3} ta="center" mb="sm" className={classes.noWorkspaceHeading}>
        No workspace for your domain
      </Title>
      <Text size="sm" c="dimmed" ta="center" mb="xl">
        Your email domain isn&apos;t linked to a workspace. Contact your admin or use your work email.
      </Text>
      <Button component="a" href={loginPath()} fullWidth size="md" variant="outline">
        Back to login
      </Button>
    </Paper>
  );
}

const loginSchema = z.object({
  email: z.string().min(1, 'Email is required').email('Invalid email format'),
  password: z.string().min(1, 'Password is required'),
  rememberMe: z.boolean().optional(),
});

const LoginPage = () => {
  const { error, email: prefillEmail, oauth_providers } = usePage<PageProps>().props;
  // Absent (an older server, or a page rendered without the prop) falls back to
  // Google alone, which is what this app offered before Microsoft existed.
  const providers = oauth_providers ?? ['google'];
  // Enterprise SSO discovery: the company is resolved from the address's domain,
  // because a member of an SSO-only company has no other way in before they are
  // signed in (the step-up screen is only reachable afterwards).
  const startSso = () => router.post(ssoDiscoveryPath(), { email: data.email });
  const passwordless = (usePage<PageProps>().props.passwordless_methods as string[] | undefined) ?? [];
  const errorShownRef = useRef(false);
  const [clientErrors, setClientErrors] = useState<Record<string, string | undefined>>({});

  // The invitation flow links here as /login?email=... (echoed back by
  // sessions#new) so the invitee only has to type their password.
  const { data, setData, post, processing, errors } = useForm({
    email: prefillEmail ?? '',
    password: '',
    rememberMe: false,
  });

  useEffect(() => {
    if (error && !errorShownRef.current) {
      const message = ERROR_MESSAGES[error] || 'Authentication failed. Please try again.';
      notifications.show({ message, color: 'red' });
      errorShownRef.current = true;
    }
  }, [error]);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const result = loginSchema.safeParse(data);
    if (!result.success) {
      const fieldErrors: Record<string, string> = {};
      for (const issue of result.error.issues) {
        const field = issue.path[0] as string;
        if (!fieldErrors[field]) fieldErrors[field] = issue.message;
      }
      setClientErrors(fieldErrors);
      return;
    }
    setClientErrors({});
    post('/login', {
      onSuccess: () => {
        notifications.show({ message: 'Welcome back!', color: 'green' });
      },
    });
  };

  return (
    <PageShell variant="centered">
      <Head title="Sign in — Aixle Flow" />
      {error === 'no_workspace' ? (
        <NoWorkspaceScreen />
      ) : error ? (
        <Paper
          className={classes.formCard}
          p="xl"
          radius="md"
          w="100%"
          maw={420}
          shadow="0 8px 32px rgba(0, 0, 0, 0.4)"
        >
          <Center mb={32}>
            <span className={classes.brand}>
              {/* No colorScheme override: pinning it to "dark" inverts the mark to
                  white, which disappears on the light-scheme login card. */}
              <Logo width={96} />
              <span className={classes.brandFlow}>Flow</span>
            </span>
          </Center>

          <Stack gap="sm">
            {providers.includes('google') && <GoogleLoginButton />}
            {providers.includes('microsoft') && <MicrosoftLoginButton />}
            <Button variant="subtle" fullWidth onClick={startSso} disabled={!data.email}>
              Sign in with your company SSO
            </Button>
            <PasswordlessOptions email={data.email} methods={passwordless} />
          </Stack>

          {providers.length > 0 && (
            <Divider label="OR" labelPosition="center" my="lg" color="var(--app-border-default)" />
          )}

          <Text ta="center" size="sm" c="dimmed" mb="lg" className={classes.subtitle}>
            Enter your credentials to access your workspace
          </Text>

          <form onSubmit={handleSubmit}>
            <Stack gap="md">
              <TextInput
                label="Email"
                value={data.email}
                onChange={(e) => {
                  setData('email', e.currentTarget.value);
                  if (clientErrors.email) setClientErrors((prev) => ({ ...prev, email: undefined }));
                }}
                placeholder="you@company.com"
                error={clientErrors.email || errors.email}
                autoComplete="username"
                classNames={{ input: classes.input, label: classes.label }}
              />

              <PasswordInput
                label="Password"
                value={data.password}
                onChange={(e) => {
                  setData('password', e.currentTarget.value);
                  if (clientErrors.password) setClientErrors((prev) => ({ ...prev, password: undefined }));
                }}
                placeholder="••••••••"
                error={clientErrors.password || errors.password}
                autoComplete="current-password"
                classNames={{ input: classes.input, label: classes.label, visibilityToggle: classes.visibilityToggle }}
                visibilityToggleButtonProps={{ 'aria-label': 'Toggle password visibility' }}
              />

              <Checkbox
                label="Remember me"
                size="sm"
                checked={data.rememberMe}
                onChange={(e) => setData('rememberMe', e.currentTarget.checked)}
              />

              <Button
                type="submit"
                fullWidth
                size="lg"
                loading={processing}
                mt="sm"
                classNames={{ root: classes.submitButton }}
              >
                {processing ? 'Signing in...' : 'Sign in'}
              </Button>
            </Stack>
          </form>

          <Text ta="center" size="xs" c="dimmed" mt="lg" className={classes.subtitle}>
            AI Agent Orchestration Platform
          </Text>
        </Paper>
      ) : (
        <Paper
          className={classes.formCard}
          p="xl"
          radius="md"
          w="100%"
          maw={420}
          shadow="0 8px 32px rgba(0, 0, 0, 0.4)"
        >
          <Center mb={32}>
            <span className={classes.brand}>
              {/* No colorScheme override: pinning it to "dark" inverts the mark to
                  white, which disappears on the light-scheme login card. */}
              <Logo width={96} />
              <span className={classes.brandFlow}>Flow</span>
            </span>
          </Center>

          <Stack gap="sm">
            {providers.includes('google') && <GoogleLoginButton />}
            {providers.includes('microsoft') && <MicrosoftLoginButton />}
            <Button variant="subtle" fullWidth onClick={startSso} disabled={!data.email}>
              Sign in with your company SSO
            </Button>
            <PasswordlessOptions email={data.email} methods={passwordless} />
          </Stack>

          {providers.length > 0 && (
            <Divider label="OR" labelPosition="center" my="lg" color="var(--app-border-default)" />
          )}

          <Text ta="center" size="sm" c="dimmed" mb="lg" className={classes.subtitle}>
            Enter your credentials to access your workspace
          </Text>

          <form onSubmit={handleSubmit}>
            <Stack gap="md">
              <TextInput
                label="Email"
                value={data.email}
                onChange={(e) => {
                  setData('email', e.currentTarget.value);
                  if (clientErrors.email) setClientErrors((prev) => ({ ...prev, email: undefined }));
                }}
                placeholder="you@company.com"
                error={clientErrors.email || errors.email}
                autoComplete="username"
                classNames={{ input: classes.input, label: classes.label }}
              />

              <PasswordInput
                label="Password"
                value={data.password}
                onChange={(e) => {
                  setData('password', e.currentTarget.value);
                  if (clientErrors.password) setClientErrors((prev) => ({ ...prev, password: undefined }));
                }}
                placeholder="••••••••"
                error={clientErrors.password || errors.password}
                autoComplete="current-password"
                classNames={{ input: classes.input, label: classes.label, visibilityToggle: classes.visibilityToggle }}
                visibilityToggleButtonProps={{ 'aria-label': 'Toggle password visibility' }}
              />

              <Checkbox
                label="Remember me"
                size="sm"
                checked={data.rememberMe}
                onChange={(e) => setData('rememberMe', e.currentTarget.checked)}
              />

              <Button
                type="submit"
                fullWidth
                size="lg"
                loading={processing}
                mt="sm"
                classNames={{ root: classes.submitButton }}
              >
                {processing ? 'Signing in...' : 'Sign in'}
              </Button>
            </Stack>
          </form>

          <Text ta="center" size="xs" c="dimmed" mt="lg" className={classes.subtitle}>
            AI Agent Orchestration Platform
          </Text>
        </Paper>
      )}
    </PageShell>
  );
};

export default LoginPage;
