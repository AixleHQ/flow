import { Head, router, useForm, usePage } from '@inertiajs/react';
import { Alert, Badge, Box, Button, Group, Paper, Stack, Switch, Text, TextInput, Title, Tooltip } from '@mantine/core';

import { AuthLayout } from 'layouts/AuthLayout';

import {
  companyAuthPolicyPath,
  companyIdentityProviderPath,
  companyIdentityProvidersPath,
  companyScimConfigurationPath,
  companySettingsPath,
  oidcStartPath,
} from 'shared/routes';

import { SettingsTabs } from './SettingsTabs';

interface Provider {
  id: number;
  kind: string;
  name: string;
  scope: string;
  enabled: boolean;
  issuer?: string | null;
  clientId?: string | null;
  tenantId?: string | null;
  hasSecret: boolean;
  proved: boolean;
}

interface ScimState {
  enabled: boolean;
  lastSeenAt?: string | null;
  endpoint?: string;
}

interface JoiningState {
  emailDomain: string | null;
  autoAcceptUsers: boolean;
}

interface PageProps {
  providers: Provider[];
  scim?: ScimState;
  joining?: JoiningState;
  company?: { name: string };
  scimToken?: string | null;
  permissions?: { isAdmin?: boolean };
  errors?: { base?: string };
  [key: string]: unknown;
}

function getCsrfToken(): string {
  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? '';
}

// A real form POST, not router.post: verifying redirects to the customer's
// identity provider, and an Inertia XHR cannot follow a cross-origin redirect —
// the browser refuses it as CORS and the page simply sits there. Same reason
// GoogleLoginButton is a form. POST rather than a link for CVE-2015-9284.
const VerifyConnectionButton = ({ providerId }: { providerId: number }) => (
  <form method="post" action={oidcStartPath(providerId)}>
    <input type="hidden" name="authenticity_token" value={getCsrfToken()} />
    <Button type="submit" size="compact-sm">
      Verify
    </Button>
  </form>
);

function ConnectionForm({ onDone }: { onDone: () => void }) {
  const form = useForm({ name: '', issuer: '', clientId: '', client_secret: '', tenantId: '' });

  return (
    <form
      onSubmit={(event) => {
        event.preventDefault();
        form.post(companyIdentityProvidersPath(), { onSuccess: onDone });
      }}
    >
      <Stack gap="sm">
        <TextInput
          label="Display name"
          placeholder="Acme SSO"
          value={form.data.name}
          onChange={(e) => form.setData('name', e.currentTarget.value)}
        />
        <TextInput
          label="Issuer URL"
          description="The OpenID Connect issuer, e.g. https://login.example.com"
          required
          value={form.data.issuer}
          onChange={(e) => form.setData('issuer', e.currentTarget.value)}
        />
        <TextInput
          label="Client ID"
          required
          value={form.data.clientId}
          onChange={(e) => form.setData('clientId', e.currentTarget.value)}
        />
        <TextInput
          label="Client secret"
          required
          value={form.data.client_secret}
          onChange={(e) => form.setData('client_secret', e.currentTarget.value)}
        />
        <Group justify="flex-end">
          <Button type="submit" loading={form.processing}>
            Add connection
          </Button>
        </Group>
      </Stack>
    </form>
  );
}

export default function AccessPage({ providers }: PageProps) {
  const page = usePage<PageProps>();
  const isAdmin = page.props.permissions?.isAdmin ?? false;
  const refusal = page.props.errors?.base;
  const joining = page.props.joining;

  const toggle = (provider: Provider, enabled: boolean) => {
    router.put(companyAuthPolicyPath(provider.id), { enabled });
  };

  // Saved on the spot, like every other control on this tab. The general tab's
  // deferred Save does not reach here, and a lone Save button for one switch
  // would be the only thing on the page that behaved differently.
  const setAutoAccept = (enabled: boolean) => {
    router.patch(companySettingsPath(), { company: { auto_accept_users: enabled } }, { preserveScroll: true });
  };

  return (
    <AuthLayout>
      <Head title="Access — company settings" />
      <SettingsTabs active="access" companyName={page.props.company?.name ?? 'this workspace'}>
        <Stack gap="md" maw={720}>
          <Title order={4}>Sign-in methods</Title>
          <Text size="sm" c="dimmed">
            Which methods this workspace accepts. Turning one off never removes anyone&apos;s credential — it stops that
            method letting someone into this workspace.
          </Text>

          {refusal && <Alert color="red">{refusal}</Alert>}

          <Paper p="md" radius="md" withBorder>
            <Stack gap="sm">
              {providers.map((provider) => (
                <Group key={provider.id} justify="space-between">
                  <Group gap="xs">
                    <Text fw={500}>{provider.name}</Text>
                    {provider.scope === 'company' && <Badge size="sm">This workspace</Badge>}
                    {provider.issuer && (
                      <Text size="xs" c="dimmed">
                        {provider.issuer}
                      </Text>
                    )}
                  </Group>
                  <Group gap="xs">
                    {!provider.proved && !provider.enabled && (
                      <Tooltip label="Verify signs you in through this connection once; until that works it cannot be enabled">
                        <Badge size="sm" color="yellow">
                          Not verified yet
                        </Badge>
                      </Tooltip>
                    )}
                    {provider.scope === 'company' && !provider.proved && isAdmin && (
                      <VerifyConnectionButton providerId={provider.id} />
                    )}
                    <Switch
                      checked={provider.enabled}
                      disabled={!isAdmin || (provider.scope === 'company' && !provider.proved)}
                      onChange={(event) => toggle(provider, event.currentTarget.checked)}
                      aria-label={`${provider.name} enabled`}
                    />
                    {provider.scope === 'company' && isAdmin && (
                      <Button
                        variant="subtle"
                        color="red"
                        size="compact-sm"
                        onClick={() => router.delete(companyIdentityProviderPath(provider.id))}
                      >
                        Remove
                      </Button>
                    )}
                  </Group>
                </Group>
              ))}
            </Stack>
          </Paper>

          {isAdmin && (
            <Paper p="md" radius="md" withBorder>
              <Stack gap="sm">
                <Group justify="space-between">
                  <Title order={4}>Directory sync (SCIM)</Title>
                  {page.props.scim?.enabled ? (
                    <Group gap="xs">
                      <Badge color="green">On</Badge>
                      <Button
                        size="compact-sm"
                        variant="subtle"
                        color="red"
                        onClick={() => router.delete(companyScimConfigurationPath())}
                      >
                        Turn off
                      </Button>
                    </Group>
                  ) : (
                    <Button size="compact-sm" onClick={() => router.post(companyScimConfigurationPath())}>
                      Generate token
                    </Button>
                  )}
                </Group>
                <Text size="sm" c="dimmed">
                  Point your identity provider at{' '}
                  <Text span ff="monospace">
                    {page.props.scim?.endpoint}
                  </Text>{' '}
                  to add and remove members automatically. Removing someone there removes their access here.
                </Text>
                {page.props.scimToken && (
                  <Alert color="yellow">
                    <Stack gap="xs">
                      <Text size="sm">Copy this token now — it is not shown again.</Text>
                      <Text ff="monospace" size="sm">
                        {page.props.scimToken}
                      </Text>
                    </Stack>
                  </Alert>
                )}
                {page.props.scim?.enabled && page.props.scim?.lastSeenAt && (
                  <Text size="xs" c="dimmed">
                    Last contacted {new Date(page.props.scim.lastSeenAt).toLocaleString()}
                  </Text>
                )}
              </Stack>
            </Paper>
          )}

          {isAdmin && (
            <Paper p="md" radius="md" withBorder>
              <Stack gap="sm">
                <Title order={4}>Connect your own identity provider</Title>
                <Text size="sm" c="dimmed">
                  A new connection arrives switched off. Verify it — that signs you in through it once — and only then
                  can it be enabled, so a misconfigured connection can never lock your workspace out.
                </Text>
                <ConnectionForm onDone={() => router.reload()} />
              </Stack>
            </Paper>
          )}

          {joining && (
            <Paper p="md" radius="md" withBorder>
              <Stack gap="sm">
                <Title order={4}>Joining</Title>
                <Box>
                  <Text fz="sm" fw={500}>
                    Email domain
                  </Text>
                  <Text fz="sm" c={joining.emailDomain ? undefined : 'dimmed'} mt={4}>
                    {joining.emailDomain ?? 'Not set'}
                  </Text>
                </Box>
                <Switch
                  label="Accept new people automatically"
                  description={
                    joining.emailDomain
                      ? `Anyone signing in with an @${joining.emailDomain} address joins without an invitation.`
                      : 'Needs an email domain — without one there is nothing to match a new person against, so everyone joins by invitation.'
                  }
                  disabled={!isAdmin || !joining.emailDomain}
                  checked={joining.autoAcceptUsers}
                  onChange={(event) => setAutoAccept(event.currentTarget.checked)}
                  aria-label="Accept new people automatically"
                />
              </Stack>
            </Paper>
          )}
        </Stack>
      </SettingsTabs>
    </AuthLayout>
  );
}
