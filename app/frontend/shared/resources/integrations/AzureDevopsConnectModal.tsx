import { router } from '@inertiajs/react';
import { Alert, Button, Checkbox, Group, Modal, PasswordInput, Select, Stack, Text, TextInput } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconAlertCircle, IconCheck } from '@tabler/icons-react';
import { useCallback, useState } from 'react';

export interface AzureDevopsProject {
  id: string;
  name: string;
}

export interface AzureDevopsProps {
  enabled: boolean;
  patModeEnabled?: boolean;
}

interface Props {
  opened: boolean;
  onClose: () => void;
  basePath: string;
  azureDevops: AzureDevopsProps;
}

// Mirrors AzureDevops::IntegrationService::ALL_CAPABILITIES. These are Aixle's
// operation profile, not Azure's ACLs: unticking one stops the request being
// sent at all, while Azure independently decides whether the identity may
// perform the ones that are sent.
const CAPABILITIES: { value: string; label: string; hint: string }[] = [
  { value: 'repositories.read', label: 'Read repositories', hint: 'Clone, fetch and inspect code' },
  { value: 'repositories.write', label: 'Push to repositories', hint: 'Create branches and push commits' },
  { value: 'pull_requests.write', label: 'Open and edit pull requests', hint: 'Never completes or merges one' },
  { value: 'pull_request_threads.write', label: 'Reply in review threads', hint: 'Comment and resolve discussions' },
  { value: 'work_items.read', label: 'Read work items', hint: 'Azure Boards tasks and comments' },
  { value: 'work_items.write', label: 'Edit work items', hint: 'Create, update and comment' },
  { value: 'builds.read', label: 'Read pipeline builds', hint: 'Build results and branch policy status' },
  {
    value: 'pull_requests.complete',
    label: 'Complete pull requests',
    hint: 'Merging. Off by default, and branch policies still apply',
  },
];

// Mirrors AzureDevops::IntegrationService::DEFAULT_CAPABILITIES. Completing pull
// requests is the one action nobody should acquire by accepting a form's
// defaults, so it starts unticked.
const DEFAULT_CAPABILITIES = CAPABILITIES.map((c) => c.value).filter((v) => v !== 'pull_requests.complete');

interface Inspection {
  organization: string;
  tenantId: string;
  identity: string | null;
  alreadyBound: boolean;
  projects: AzureDevopsProject[];
}

// These two endpoints answer JSON rather than an Inertia redirect, because the
// modal keeps its state across the two steps.
const postJson = async (url: string, body: Record<string, unknown>) => {
  const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? '';
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': token, Accept: 'application/json' },
    body: JSON.stringify(body),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload.message || 'Azure DevOps rejected the request');
  return payload;
};

export const AzureDevopsConnectModal = ({ opened, onClose, basePath, azureDevops }: Props) => {
  const patAvailable = !!azureDevops.patModeEnabled;

  const [authMode, setAuthMode] = useState<'service_principal' | 'pat'>('service_principal');
  const [organization, setOrganization] = useState('');
  const [adminPat, setAdminPat] = useState('');
  const [inspection, setInspection] = useState<Inspection | null>(null);
  const [projectId, setProjectId] = useState<string | null>(null);

  const [patProjectId, setPatProjectId] = useState('');
  const [pat, setPat] = useState('');

  const [capabilities, setCapabilities] = useState<string[]>(DEFAULT_CAPABILITIES);
  const [verifying, setVerifying] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const reset = useCallback(() => {
    setAuthMode('service_principal');
    setOrganization('');
    setAdminPat('');
    setInspection(null);
    setProjectId(null);
    setPatProjectId('');
    setPat('');
    setCapabilities(DEFAULT_CAPABILITIES);
    setError(null);
  }, []);

  const close = useCallback(() => {
    onClose();
    reset();
  }, [onClose, reset]);

  // Step one: prove this company may bind the organization at all, and see what
  // it holds. An organization already bound needs no token — the binding is the
  // proof, established once by someone who demonstrated control.
  const verify = useCallback(async () => {
    if (!organization.trim()) return;
    setError(null);
    setVerifying(true);
    try {
      const result = (await postJson(`${basePath}/azure_devops_inspect`, {
        organization: organization.trim(),
        personal_access_token: adminPat.trim(),
      })) as Inspection;
      setInspection(result);
      setProjectId(result.projects[0]?.id ?? null);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not verify the organization');
    } finally {
      setVerifying(false);
    }
  }, [adminPat, basePath, organization]);

  // Step two: entitle the application in the organization, record the binding,
  // then create the project connection on top of it.
  const connect = useCallback(async () => {
    if (!inspection || !projectId) return;
    setError(null);
    setLoading(true);
    try {
      const bound = (await postJson(`${basePath}/azure_devops_connect`, {
        organization: inspection.organization,
        personal_access_token: adminPat.trim(),
        project_ids: [projectId],
      })) as { installationId: number };

      // The token has done its job and does not outlive it — on the server it
      // was never written down, and here it leaves component state now.
      setAdminPat('');

      router.post(
        basePath,
        {
          provider: 'azure_devops',
          authMode: 'service_principal',
          azureDevopsInstallationId: String(bound.installationId),
          azureProjectId: projectId,
          enabledCapabilities: capabilities,
        },
        {
          preserveScroll: true,
          onSuccess: () => close(),
          onError: (errors) => {
            const message = typeof errors === 'object' && errors ? Object.values(errors).join(' ') : '';
            setError(message || 'Failed to connect Azure DevOps');
          },
          onFinish: () => setLoading(false),
        },
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not connect Azure DevOps');
      setLoading(false);
    }
  }, [adminPat, basePath, capabilities, close, inspection, projectId]);

  const submitPat = useCallback(() => {
    if (!organization.trim() || !patProjectId.trim() || !pat.trim()) return;
    setError(null);
    setLoading(true);
    router.post(
      basePath,
      {
        provider: 'azure_devops',
        authMode: 'pat',
        organizationSlug: organization.trim(),
        azureProjectId: patProjectId.trim(),
        personalAccessToken: pat.trim(),
        enabledCapabilities: capabilities,
      },
      {
        preserveScroll: true,
        onSuccess: () => close(),
        onError: (errors) => {
          const message = typeof errors === 'object' && errors ? Object.values(errors).join(' ') : '';
          setError(message || 'Failed to connect Azure DevOps');
          notifications.show({ message: 'Failed to connect Azure DevOps', color: 'red' });
        },
        onFinish: () => {
          setLoading(false);
          setPat('');
        },
      },
    );
  }, [basePath, capabilities, close, organization, pat, patProjectId]);

  const missingPrincipal = !!error && error.includes('missing a service principal');

  return (
    <Modal opened={opened} onClose={close} title="Connect Azure DevOps" centered size="lg">
      <Stack gap="md">
        {authMode === 'service_principal' ? (
          <>
            <TextInput
              label="Azure organization"
              description="The name in https://dev.azure.com/<organization>"
              placeholder="contoso"
              value={organization}
              onChange={(e) => {
                setOrganization(e.currentTarget.value);
                setInspection(null);
              }}
              disabled={!!inspection}
            />

            {!inspection && (
              <>
                <PasswordInput
                  label="Administrator personal access token"
                  description="Used once, in this request, to prove the organization is yours and to add Aixle to it. It is never stored, and the connection runs on Aixle's own identity afterwards. Needs the Member Entitlement Management (read & write) scope. Leave empty if your company has already connected this organization."
                  value={adminPat}
                  onChange={(e) => setAdminPat(e.currentTarget.value)}
                />
                <Group justify="flex-end">
                  <Button onClick={verify} loading={verifying} disabled={!organization.trim()}>
                    Verify organization
                  </Button>
                </Group>
              </>
            )}

            {inspection && (
              <>
                <Alert color="green" icon={<IconCheck size={16} />} title="Organization verified">
                  <Text size="sm">
                    {inspection.alreadyBound
                      ? 'Your company has already connected this organization, so no token was needed.'
                      : `Verified${inspection.identity ? ` as ${inspection.identity}` : ''}. Aixle will be added to this organization with a Basic access level.`}
                  </Text>
                </Alert>
                <Select
                  label="Azure project"
                  description="This connection works against one project. The selection cannot be changed later — connect again to work against another."
                  placeholder="Select a project"
                  data={inspection.projects.map((p) => ({ value: p.id, label: p.name }))}
                  value={projectId}
                  onChange={setProjectId}
                  allowDeselect={false}
                  searchable
                />
              </>
            )}
          </>
        ) : (
          <>
            <Alert color="orange" icon={<IconAlertCircle size={16} />} title="This acts as you, not as Aixle">
              <Text size="sm">
                A personal access token carries its owner&apos;s own Azure permissions, and pull requests and comments
                are attributed to that person. It is meant for a pilot, or for an organization on a personal Microsoft
                account, where a service principal cannot be used at all.
              </Text>
            </Alert>
            <TextInput
              label="Organization"
              description="The name in https://dev.azure.com/<organization>"
              placeholder="contoso"
              value={organization}
              onChange={(e) => setOrganization(e.currentTarget.value)}
            />
            <TextInput
              label="Azure project ID"
              description="The project's GUID, from Project settings → Overview"
              placeholder="00000000-0000-0000-0000-000000000000"
              value={patProjectId}
              onChange={(e) => setPatProjectId(e.currentTarget.value)}
            />
            <PasswordInput
              label="Personal access token"
              description="Scoped to this organization. Stored encrypted and never shown again."
              value={pat}
              onChange={(e) => setPat(e.currentTarget.value)}
            />
          </>
        )}

        <Checkbox.Group
          label="What agents may do"
          description="Unticking one stops Aixle sending that kind of request at all. Azure still decides separately whether the identity is permitted."
          value={capabilities}
          onChange={setCapabilities}
        >
          <Stack gap={6} mt="xs">
            {CAPABILITIES.map((capability) => (
              <Checkbox
                key={capability.value}
                value={capability.value}
                label={
                  <span>
                    {capability.label}{' '}
                    <Text component="span" fz={12} c="dimmed">
                      — {capability.hint}
                    </Text>
                  </span>
                }
              />
            ))}
          </Stack>
        </Checkbox.Group>

        {error && (
          <Alert color="red" icon={<IconAlertCircle size={16} />}>
            {error}
            {missingPrincipal && (
              <Text size="sm" mt="xs">
                Aixle&apos;s application has not been added to your Microsoft Entra directory yet. A directory
                administrator runs <code>az ad sp create --id &lt;client id&gt;</code> once — nothing is consented to
                and no permission is granted, it only makes the application nameable in your organization.
              </Text>
            )}
          </Alert>
        )}

        <Group justify="space-between">
          {patAvailable ? (
            <Button
              variant="subtle"
              size="compact-sm"
              onClick={() => {
                setAuthMode(authMode === 'pat' ? 'service_principal' : 'pat');
                setInspection(null);
                setError(null);
              }}
            >
              {authMode === 'pat' ? 'Use Aixle’s own identity instead' : 'Use a personal access token instead'}
            </Button>
          ) : (
            <span />
          )}
          <Group gap="sm">
            <Button variant="default" onClick={close}>
              Cancel
            </Button>
            {authMode === 'pat' ? (
              <Button
                onClick={submitPat}
                loading={loading}
                disabled={!organization.trim() || !patProjectId.trim() || !pat.trim()}
              >
                Connect
              </Button>
            ) : (
              <Button onClick={connect} loading={loading} disabled={!inspection || !projectId}>
                Connect
              </Button>
            )}
          </Group>
        </Group>
      </Stack>
    </Modal>
  );
};
