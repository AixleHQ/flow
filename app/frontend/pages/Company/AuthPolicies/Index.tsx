import { Head, router, useForm, usePage } from '@inertiajs/react';
import { Alert, Badge, Button, Group, Paper, Stack, Switch, Text, TextInput, Title, Tooltip } from '@mantine/core';

import { AuthLayout } from 'layouts/AuthLayout';

import {
  companyAuthPolicyPath,
  companyIdentityProviderPath,
  companyIdentityProvidersPath,
  companyScimConfigurationPath,
  oidcStartPath,
} from 'shared/routes';

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

interface PageProps {
  providers: Provider[];
  scim?: ScimState;
  scimToken?: string | null;
  permissions?: { isAdmin?: boolean };
  errors?: { base?: string };
  [key: string]: unknown;
}

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

export default function AuthPoliciesIndex({ providers }: PageProps) {
  const page = usePage<PageProps>();
  const isAdmin = page.props.permissions?.isAdmin ?? false;
  const refusal = page.props.errors?.base;

  const toggle = (provider: Provider, enabled: boolean) => {
    router.put(companyAuthPolicyPath(provider.id), { enabled });
  };

  return (
    <AuthLayout>
      <Stack gap="md">
        <Head title="Sign-in methods" />
        <Title order={2}>Sign-in methods</Title>
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
                    <Button size="compact-sm" onClick={() => router.post(oidcStartPath(provider.id))}>
                      Verify
                    </Button>
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
                A new connection arrives switched off. Verify it — that signs you in through it once — and only then can
                it be enabled, so a misconfigured connection can never lock your workspace out.
              </Text>
              <ConnectionForm onDone={() => router.reload()} />
            </Stack>
          </Paper>
        )}
      </Stack>
    </AuthLayout>
  );
}
