import { router } from '@inertiajs/react';
import {
  ActionIcon,
  Alert,
  Button,
  Code,
  CopyButton,
  Group,
  MultiSelect,
  Radio,
  Stack,
  Switch,
  Text,
  TextInput,
  Tooltip,
} from '@mantine/core';
import { IconAlertCircle, IconCheck, IconCopy, IconHelpCircle, IconX } from '@tabler/icons-react';
import { useCallback, useEffect, useState } from 'react';

import { type AzureDevopsProject, capabilitiesChanged, postJson } from './azureDevopsShared';
import { CapabilityPicker } from './CapabilityPicker';

/** What the customer enters in the federated credential of their own Entra app. None of it is secret. */
export interface AzureDevopsFederation {
  issuerUrl: string;
  audience: string;
  subject: string;
}

type Status = 'granted' | 'missing' | 'unknown';

interface PermissionItem {
  key: string;
  group: string;
  label: string;
  required: boolean;
  status: Status;
}

interface PermissionReport {
  ok: boolean;
  projects: { id: string; name: string; items: PermissionItem[] }[];
}

interface Inspection {
  organization: string;
  tenantId: string;
  alreadyBound: boolean;
  projects: AzureDevopsProject[];
  permissions: PermissionReport | null;
}

interface Props {
  basePath: string;
  federation: AzureDevopsFederation;
  capabilities: string[];
  onCapabilitiesChange: (value: string[]) => void;
  onDirtyChange: (dirty: boolean) => void;
  onCancel: () => void;
  onConnected: () => void;
}

const GUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const CopyField = ({ label, value }: { label: string; value: string }) => (
  <TextInput
    label={label}
    value={value}
    readOnly
    rightSection={
      <CopyButton value={value}>
        {({ copied, copy }) => (
          <Tooltip label={copied ? 'Copied' : 'Copy'}>
            <ActionIcon variant="subtle" color={copied ? 'teal' : 'gray'} onClick={copy} aria-label={`Copy ${label}`}>
              {copied ? <IconCheck size={16} /> : <IconCopy size={16} />}
            </ActionIcon>
          </Tooltip>
        )}
      </CopyButton>
    }
  />
);

const StatusIcon = ({ status }: { status: Status }) => {
  if (status === 'granted') return <IconCheck size={14} color="var(--mantine-color-teal-6)" aria-label="granted" />;
  if (status === 'missing') return <IconX size={14} color="var(--mantine-color-red-6)" aria-label="missing" />;
  return <IconHelpCircle size={14} color="var(--mantine-color-gray-6)" aria-label="could not be checked" />;
};

const PermissionTable = ({ report }: { report: PermissionReport }) => (
  <Stack gap="xs">
    {report.projects.map((project) => (
      <div key={project.id}>
        <Text size="sm" fw={600}>
          {project.name || project.id}
        </Text>
        {project.items.map((item) => (
          <Group key={item.key} gap={6} wrap="nowrap">
            <StatusIcon status={item.status} />
            <Text size="sm">
              {item.group}: {item.label}
              {item.required ? '' : ' (optional)'}
              {item.status === 'unknown' ? ' — could not be checked' : ''}
            </Text>
          </Group>
        ))}
      </div>
    ))}
  </Stack>
);

export const AzureDevopsFederatedForm = ({
  basePath,
  federation,
  capabilities,
  onCapabilitiesChange,
  onDirtyChange,
  onCancel,
  onConnected,
}: Props) => {
  const [organization, setOrganization] = useState('');
  const [clientId, setClientId] = useState('');
  const [flavor, setFlavor] = useState<'contributors' | 'custom'>('contributors');
  const [serviceHooks, setServiceHooks] = useState(true);
  const [script, setScript] = useState<string | null>(null);
  const [inspection, setInspection] = useState<Inspection | null>(null);
  const [projectIds, setProjectIds] = useState<string[]>([]);
  const [busy, setBusy] = useState<'script' | 'inspect' | 'connect' | null>(null);
  const [error, setError] = useState<string | null>(null);

  const clientIdValid = GUID.test(clientId.trim());
  const ready = organization.trim() !== '' && clientIdValid;

  useEffect(() => {
    onDirtyChange(organization !== '' || clientId !== '' || projectIds.length > 0 || capabilitiesChanged(capabilities));
  }, [capabilities, clientId, onDirtyChange, organization, projectIds.length]);

  const changed = () => {
    setInspection(null);
    setScript(null);
    setProjectIds([]);
  };

  const request = useCallback(
    async (kind: 'script' | 'inspect', body: Record<string, unknown>) => {
      setError(null);
      setBusy(kind);
      try {
        return await postJson(`${basePath}/azure_devops_federated_${kind}`, {
          organization: organization.trim(),
          client_id: clientId.trim(),
          ...body,
        });
      } catch (e) {
        setError(e instanceof Error ? e.message : 'Azure DevOps rejected the request');
        return null;
      } finally {
        setBusy(null);
      }
    },
    [basePath, clientId, organization],
  );

  const generateScript = async () => {
    const result = await request('script', { flavor, service_hooks: serviceHooks });
    if (result) setScript(result.script as string);
  };

  const check = async (ids: string[]) => {
    const result = (await request('inspect', ids.length > 0 ? { project_ids: ids } : {})) as Inspection | null;
    if (!result) return;
    setInspection(result);
    // Keep the choice only for projects that are still visible.
    setProjectIds((current) => current.filter((id) => result.projects.some((p) => p.id === id)));
  };

  const connect = async () => {
    if (!inspection || projectIds.length === 0) return;
    setError(null);
    setBusy('connect');
    try {
      const bound = (await postJson(`${basePath}/azure_devops_federated_connect`, {
        organization: inspection.organization,
        client_id: clientId.trim(),
        project_ids: projectIds,
      })) as { installationId: number };

      router.post(
        basePath,
        {
          provider: 'azure_devops',
          authMode: 'service_principal',
          azureDevopsInstallationId: String(bound.installationId),
          azureProjectIds: projectIds,
          azureProjectNames: Object.fromEntries(
            inspection.projects.filter((p) => projectIds.includes(p.id)).map((p) => [p.id, p.name]),
          ),
          enabledCapabilities: capabilities,
        },
        {
          preserveScroll: true,
          onSuccess: () => onConnected(),
          onError: (errors) => {
            const message = typeof errors === 'object' && errors ? Object.values(errors).join(' ') : '';
            setError(message || 'Failed to connect Azure DevOps');
          },
          onFinish: () => setBusy(null),
        },
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not connect Azure DevOps');
      setBusy(null);
    }
  };

  return (
    <Stack gap="md">
      <Alert color="gray" variant="light" title="1. In your Microsoft Entra directory">
        <Text size="sm">
          Register a single-tenant app. Under Certificates &amp; secrets → Federated credentials, add a credential with
          the scenario <b>Other issuer</b> and these values. Entra accepts a mistyped subject when it is saved and only
          refuses it later, so copy them exactly: the subject is case-sensitive.
        </Text>
        <Stack gap="xs" mt="xs">
          <CopyField label="Issuer" value={federation.issuerUrl} />
          <CopyField label="Subject identifier" value={federation.subject} />
          <CopyField label="Audience" value={federation.audience} />
        </Stack>
        <Text size="sm" mt="xs" c="dimmed">
          No secret or certificate is created or stored. Deleting this credential, or the app, ends Aixle&apos;s access
          at once.
        </Text>
      </Alert>

      <Alert color="gray" variant="light" title="2. In Azure DevOps">
        <Text size="sm">
          A Project Collection Administrator adds the app to your organization once and grants it access to the projects
          agents work in. Aixle never receives their token. Enter your organization and the app&apos;s Application
          (client) ID to get the script.
        </Text>
        <Stack gap="xs" mt="xs">
          <TextInput
            label="Azure organization"
            description="The name in https://dev.azure.com/<organization>"
            placeholder="contoso"
            value={organization}
            onChange={(e) => {
              setOrganization(e.currentTarget.value);
              changed();
            }}
          />
          <TextInput
            label="Application (client) ID"
            placeholder="00000000-0000-0000-0000-000000000000"
            value={clientId}
            onChange={(e) => {
              setClientId(e.currentTarget.value);
              changed();
            }}
            error={clientId.trim() && !clientIdValid ? 'Must be a GUID' : undefined}
          />
          <Radio.Group
            label="Permissions to grant"
            value={flavor}
            onChange={(value) => {
              setFlavor(value as 'contributors' | 'custom');
              setScript(null);
            }}
          >
            <Stack gap="xs" mt="xs">
              <Radio
                value="contributors"
                label="Contributors group (Recommended)"
                description="Basic access and the project's Contributors group. Not the Azure RBAC Contributor role."
              />
              <Radio
                value="custom"
                label="Only what Aixle needs"
                description="Repos (read, contribute, create branch, contribute to pull requests), Boards (view and edit work items), Pipelines (view builds)."
              />
            </Stack>
          </Radio.Group>
          <Switch
            checked={serviceHooks}
            onChange={(e) => {
              setServiceHooks(e.currentTarget.checked);
              setScript(null);
            }}
            label="Service Hooks permission"
            description="View and edit subscriptions. Only needed for instant CI gates and Boards triggers."
          />
          <Group>
            <Button variant="default" onClick={generateScript} loading={busy === 'script'} disabled={!ready}>
              Show setup script
            </Button>
          </Group>
          {script && (
            <>
              <Code block>{script}</Code>
              <CopyButton value={script}>
                {({ copied, copy }) => (
                  <Button variant="subtle" size="compact-sm" onClick={copy}>
                    {copied ? 'Copied' : 'Copy script'}
                  </Button>
                )}
              </CopyButton>
              <Text size="sm" c="dimmed">
                Run it after <Code>az login</Code>, naming the projects:{' '}
                <Code>./aixle-azure-devops.sh &quot;Project A&quot;</Code>. Pushing a branch can start your pipelines;
                your branch policies and environment approvals apply to Aixle exactly as they do to any developer.
              </Text>
            </>
          )}
        </Stack>
      </Alert>

      <Alert color="gray" variant="light" title="3. Check and connect">
        <Group>
          <Button onClick={() => check([])} loading={busy === 'inspect' && !inspection} disabled={!ready}>
            Verify access
          </Button>
        </Group>

        {inspection && (
          <Stack gap="xs" mt="xs">
            <Alert color="green" icon={<IconCheck size={16} />} title="Aixle can sign in as your app">
              <Text size="sm">
                {inspection.alreadyBound
                  ? 'This organization is already connected with your app; choosing more projects widens it.'
                  : 'Entra accepted the credential, and Azure DevOps lists the projects below.'}
              </Text>
            </Alert>
            <MultiSelect
              label="Azure projects"
              description="Everything this connection can reach. Repositories, work items and builds outside these projects stay out of reach."
              placeholder={projectIds.length === 0 ? 'Select one or more projects' : undefined}
              data={inspection.projects.map((p) => ({ value: p.id, label: p.name }))}
              value={projectIds}
              onChange={(ids) => {
                setProjectIds(ids);
                if (ids.length > 0) void check(ids);
                else setInspection((current) => (current ? { ...current, permissions: null } : current));
              }}
              searchable
              clearable
            />
            {inspection.permissions && (
              <>
                {!inspection.permissions.ok && (
                  <Alert color="red" icon={<IconAlertCircle size={16} />} title="Permissions are missing">
                    <Text size="sm">
                      Run the setup script, or grant the missing permissions in Azure DevOps, then verify again.
                    </Text>
                  </Alert>
                )}
                <PermissionTable report={inspection.permissions} />
              </>
            )}
          </Stack>
        )}
      </Alert>

      <CapabilityPicker value={capabilities} onChange={onCapabilitiesChange} />

      {error && (
        <Alert color="red" icon={<IconAlertCircle size={16} />}>
          {error}
        </Alert>
      )}

      <Group justify="flex-end">
        <Button variant="default" onClick={onCancel}>
          Cancel
        </Button>
        <Button
          onClick={connect}
          loading={busy === 'connect'}
          disabled={!inspection || projectIds.length === 0 || inspection.permissions?.ok === false}
        >
          Connect
        </Button>
      </Group>
    </Stack>
  );
};
