import { Head, router, usePage } from '@inertiajs/react';
import { Button, Center, Divider, Group, Paper, PasswordInput, Stack, Text, TextInput, Title } from '@mantine/core';
import { useForm } from '@mantine/form';
import { zod4Resolver as zodResolver } from 'mantine-form-zod-resolver';
import { useEffect, useState } from 'react';
import { z } from 'zod';

import { Logo, PageShell } from 'shared/ui';

import { GoogleLoginButton } from '../Auth/GoogleLoginButton';

type Variant = 'expired' | 'accept' | 'wrong_account' | 'login' | 'signup';

interface Props {
  variant: Variant;
  token: string;
  company?: { name: string };
  role?: string;
  inviterName?: string | null;
  invitedEmail?: string;
  currentEmail?: string;
  inviteeName?: string;
}

interface PageErrors {
  errors?: Record<string, string | string[]>;
  [key: string]: unknown;
}

const ROLE_LABELS: Record<string, string> = {
  employee: 'Employee',
  admin: 'Admin',
  viewer: 'Viewer',
};

const signupSchema = z
  .object({
    name: z.string().min(1, 'Name is required'),
    password: z.string().min(8, 'Password must be at least 8 characters'),
    passwordConfirmation: z.string().min(1, 'Password confirmation is required'),
  })
  .refine((data) => data.password === data.passwordConfirmation, {
    message: 'Passwords do not match',
    path: ['passwordConfirmation'],
  });

type SignupFormData = z.infer<typeof signupSchema>;

const firstError = (value: string | string[] | undefined): string | undefined =>
  Array.isArray(value) ? value[0] : value;

const InvitationSummary = ({ inviterName, company, role }: Pick<Props, 'inviterName' | 'company' | 'role'>) => (
  <Text ta="center" size="sm" c="dimmed" mb="lg">
    {inviterName ?? 'An administrator'} invited you to join <strong>{company?.name}</strong> as{' '}
    <strong>{ROLE_LABELS[role ?? ''] ?? role}</strong>.
  </Text>
);

const SignupForm = ({ token, inviteeName }: { token: string; inviteeName?: string }) => {
  const { errors: serverErrors } = usePage<PageErrors>().props;
  const [loading, setLoading] = useState(false);

  const form = useForm<SignupFormData>({
    validate: zodResolver(signupSchema),
    initialValues: {
      name: inviteeName ?? '',
      password: '',
      passwordConfirmation: '',
    },
  });

  useEffect(() => {
    if (!serverErrors) return;
    form.setErrors({
      name: firstError(serverErrors.name),
      password: firstError(serverErrors.password),
      passwordConfirmation: firstError(serverErrors.password_confirmation ?? serverErrors.passwordConfirmation),
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [serverErrors]);

  const handleSubmit = (values: SignupFormData) => {
    setLoading(true);
    router.post(
      `/invitations/${token}/signup`,
      {
        name: values.name,
        password: values.password,
        password_confirmation: values.passwordConfirmation,
      },
      { onFinish: () => setLoading(false) },
    );
  };

  return (
    <form onSubmit={form.onSubmit(handleSubmit)}>
      <Stack gap="md">
        <TextInput label="Full Name" placeholder="John Doe" {...form.getInputProps('name')} />
        <PasswordInput
          label="Password"
          placeholder="••••••••"
          autoComplete="new-password"
          {...form.getInputProps('password')}
        />
        <PasswordInput
          label="Confirm Password"
          placeholder="••••••••"
          autoComplete="new-password"
          {...form.getInputProps('passwordConfirmation')}
        />
        <Button type="submit" fullWidth loading={loading} mt="sm">
          Create account & join
        </Button>
      </Stack>
    </form>
  );
};

function InvitationShow(props: Props) {
  const { variant, token, company, role, inviterName, invitedEmail, currentEmail, inviteeName } = props;

  return (
    <PageShell variant="centered">
      <Head title="Invitation" />
      <Paper p="xl" radius="md" w="100%" maw={440} withBorder>
        <Center mb={24}>
          <Logo width={96} />
        </Center>

        {variant === 'expired' && (
          <Stack gap="md">
            <Title order={3} ta="center">
              Invitation link is no longer valid
            </Title>
            <Text ta="center" size="sm" c="dimmed">
              This invitation has expired or was already used. Ask a company administrator to send you a new one.
            </Text>
            <Button variant="default" fullWidth onClick={() => router.visit('/login')}>
              Go to login
            </Button>
          </Stack>
        )}

        {variant === 'accept' && (
          <Stack gap="md">
            <Title order={3} ta="center">
              Join {company?.name}
            </Title>
            <InvitationSummary inviterName={inviterName} company={company} role={role} />
            <Group grow>
              <Button variant="default" onClick={() => router.post(`/invitations/${token}/decline`)}>
                Decline
              </Button>
              <Button onClick={() => router.post(`/invitations/${token}/accept`)}>Accept invitation</Button>
            </Group>
          </Stack>
        )}

        {variant === 'wrong_account' && (
          <Stack gap="md">
            <Title order={3} ta="center">
              This invitation is for someone else
            </Title>
            <Text ta="center" size="sm" c="dimmed">
              The invitation to <strong>{company?.name}</strong> was sent to <strong>{invitedEmail}</strong>, but you
              are signed in as <strong>{currentEmail}</strong>.
            </Text>
            <Button
              fullWidth
              onClick={() =>
                router.delete('/logout', {
                  onFinish: () => router.visit(`/invitations/${token}`),
                })
              }
            >
              Log out and continue
            </Button>
          </Stack>
        )}

        {variant === 'login' && (
          <Stack gap="md">
            <Title order={3} ta="center">
              Join {company?.name}
            </Title>
            <InvitationSummary inviterName={inviterName} company={company} role={role} />
            <Text ta="center" size="sm" c="dimmed">
              Sign in as <strong>{invitedEmail}</strong> to accept the invitation — it will be applied automatically
              after login.
            </Text>
            <Button
              fullWidth
              onClick={() => router.visit(invitedEmail ? `/login?email=${encodeURIComponent(invitedEmail)}` : '/login')}
            >
              Sign in to accept
            </Button>
          </Stack>
        )}

        {variant === 'signup' && (
          <Stack gap="md">
            <Title order={3} ta="center">
              Join {company?.name}
            </Title>
            <InvitationSummary inviterName={inviterName} company={company} role={role} />
            <Text ta="center" size="sm" c="dimmed">
              Sign in with Google as <strong>{invitedEmail}</strong>, or create a password to get started.
            </Text>
            <GoogleLoginButton size="md">Continue with Google</GoogleLoginButton>
            <Divider label="OR" labelPosition="center" />
            <SignupForm token={token} inviteeName={inviteeName} />
          </Stack>
        )}
      </Paper>
    </PageShell>
  );
}

export default InvitationShow;
