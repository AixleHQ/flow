import { Head, router, useForm, usePage } from '@inertiajs/react';
import { Button, Center, Checkbox, Divider, Paper, PasswordInput, Stack, Text, TextInput, Title } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconArrowLeft } from '@tabler/icons-react';
import { useEffect, useRef, useState } from 'react';
import { z } from 'zod';

import { GoogleLoginButton } from 'shared/components/GoogleLoginButton';
import { loginIdentifyPath, loginPath } from 'shared/routes';
import { Logo, PageShell } from 'shared/ui';

import classes from './LoginPage.module.css';
import { MicrosoftLoginButton } from './MicrosoftLoginButton';
import { PasswordlessOptions } from './PasswordlessOptions';

interface PageProps {
  error?: string;
  email?: string;
  /** Redirect providers this installation offers. Absent means Google only. */
  oauthProviders?: string[];
  passwordlessMethods?: string[];
  /** Present only on step two, once an address has resolved to a workspace. */
  step?: 'credentials';
  companyName?: string;
  /** Exactly what this workspace accepts. Nothing else is drawn. */
  methods?: string[];
  dead_end?: boolean;
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

// Split by step. The address is settled on step one and is not editable on
// step two, so a complaint about it there would have nowhere to appear.
const emailSchema = z.string().min(1, 'Email is required').email('Invalid email format');
const passwordSchema = z.string().min(1, 'Password is required');

const LoginPage = () => {
  const { error, email: prefillEmail, oauthProviders } = usePage<PageProps>().props;
  // Absent (an older server, or a page rendered without the prop) falls back to
  // Google alone, which is what this app offered before Microsoft existed.
  const providers = oauthProviders ?? ['google'];
  const step = usePage<PageProps>().props.step;
  const companyName = usePage<PageProps>().props.companyName;
  const acceptedMethods = (usePage<PageProps>().props.methods as string[] | undefined) ?? [];
  const deadEnd = usePage<PageProps>().props.dead_end === true;
  const passwordless = (usePage<PageProps>().props.passwordlessMethods as string[] | undefined) ?? [];
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
    const result = passwordSchema.safeParse(data.password);
    if (!result.success) {
      setClientErrors({ password: result.error.issues[0].message });
      return;
    }
    setClientErrors({});
    post('/login', {
      onSuccess: () => {
        notifications.show({ message: 'Welcome back!', color: 'green' });
      },
    });
  };

  const identify = (e: React.FormEvent) => {
    e.preventDefault();
    const result = emailSchema.safeParse(data.email.trim());
    if (!result.success) {
      setClientErrors({ email: result.error.issues[0].message });
      return;
    }
    setClientErrors({});
    router.post(loginIdentifyPath(), { email: data.email.trim() });
  };

  const emailField = (
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
      autoFocus
      classNames={{ input: classes.input, label: classes.label }}
    />
  );

  const brand = (
    <Center mb={32}>
      <span className={classes.brand}>
        {/* No colorScheme override: pinning it to "dark" inverts the mark to
            white, which disappears on the light-scheme login card. */}
        <Logo width={96} />
        <span className={classes.brandFlow}>Flow</span>
      </span>
    </Center>
  );

  const card = (children: React.ReactNode) => (
    <Paper className={classes.formCard} p="xl" radius="md" w="100%" maw={420} shadow="0 8px 32px rgba(0, 0, 0, 0.4)">
      {brand}
      {children}
      <Text ta="center" size="xs" c="dimmed" mt="lg" className={classes.subtitle}>
        AI Agent Orchestration Platform
      </Text>
    </Paper>
  );

  if (error === 'no_workspace') {
    return (
      <PageShell variant="centered">
        <Head title="Sign in — Aixle Flow" />
        <NoWorkspaceScreen />
      </PageShell>
    );
  }

  // Step two. Only what this workspace actually accepts is drawn — a method it
  // does not take is never offered and then refused.
  if (step === 'credentials') {
    return (
      <PageShell variant="centered">
        <Head title={`Sign in to ${companyName ?? 'Aixle Flow'}`} />
        {card(
          <Stack gap="md">
            <Button
              variant="default"
              size="compact-sm"
              radius="xl"
              leftSection={<IconArrowLeft size={14} />}
              onClick={() => router.get(loginPath())}
              style={{ alignSelf: 'flex-start' }}
            >
              {prefillEmail ?? data.email}
            </Button>

            {deadEnd ? (
              <Text size="sm" c="dimmed">
                {companyName} accepts no sign-in method at the moment. Ask an administrator of that workspace to turn
                one on.
              </Text>
            ) : (
              <>
                {acceptedMethods.includes('password') && (
                  <form onSubmit={handleSubmit}>
                    <Stack gap="md">
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
                        autoFocus
                        classNames={{
                          input: classes.input,
                          label: classes.label,
                          visibilityToggle: classes.visibilityToggle,
                        }}
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
                        classNames={{ root: classes.submitButton }}
                      >
                        {processing ? 'Signing in...' : 'Sign in'}
                      </Button>
                    </Stack>
                  </form>
                )}

                <Stack gap="sm">
                  {acceptedMethods.includes('google') && <GoogleLoginButton />}
                  {acceptedMethods.includes('microsoft') && <MicrosoftLoginButton />}
                  <PasswordlessOptions email={data.email} methods={acceptedMethods} />
                </Stack>
              </>
            )}
          </Stack>,
        )}
      </PageShell>
    );
  }

  // Step one: the address, and the methods that identify a person without it.
  return (
    <PageShell variant="centered">
      <Head title="Sign in — Aixle Flow" />
      {card(
        <>
          <form onSubmit={identify}>
            <Stack gap="xs">
              {emailField}
              <Text size="xs" c="dimmed" className={classes.subtitle}>
                Your address decides which workspace you land in, and how it lets you in.
              </Text>
              <Button type="submit" fullWidth size="lg" mt="sm" classNames={{ root: classes.submitButton }}>
                Continue
              </Button>
            </Stack>
          </form>

          <Divider label="or" labelPosition="center" my="lg" color="var(--app-border-default)" />

          <Stack gap="sm">
            {providers.includes('google') && <GoogleLoginButton />}
            {providers.includes('microsoft') && <MicrosoftLoginButton />}
            <PasswordlessOptions email={data.email} methods={passwordless.filter((m) => m === 'passkey')} />
          </Stack>
        </>,
      )}
    </PageShell>
  );
};

export default LoginPage;
