import { router } from '@inertiajs/react';
import { Alert, Button, Checkbox, Group, Modal, PasswordInput, Select, Stack, Text, TextInput } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconAlertCircle } from '@tabler/icons-react';
import { useCallback, useEffect, useMemo, useState } from 'react';

export interface AzureDevopsProject {
  id: string;
  name: string;
  description?: string | null;
}

export interface AzureDevopsInstallation {
  id: number;
  organizationSlug: string;
  tenantId: string;
  status: string;
  lastVerifiedAt?: string | null;
  // Absent until this installation is the one asked about: the server lists an
  // organization's projects only on request, so the integrations page does not
  // make a live Azure call for every visitor.
  projects?: AzureDevopsProject[];
}

export interface AzureDevopsProps {
  enabled: boolean;
  patModeEnabled?: boolean;
  installations?: AzureDevopsInstallation[];
}

interface Props {
  opened: boolean;
  onClose: () => void;
  basePath: string;
  azureDevops: AzureDevopsProps;
}

// Mirrors AzureDevops::IntegrationService::DEFAULT_CAPABILITIES. These are
// Aixle's operation profile, not Azure's ACLs: unticking one stops the request
// being sent at all, while Azure independently decides whether the identity may
// perform the ones that are sent.
const CAPABILITIES: { value: string; label: string; hint: string }[] = [
  { value: 'repositories.read', label: 'Read repositories', hint: 'Clone, fetch and inspect code' },
  { value: 'repositories.write', label: 'Push to repositories', hint: 'Create branches and push commits' },
  { value: 'pull_requests.write', label: 'Open and edit pull requests', hint: 'Never completes or merges one' },
  { value: 'pull_request_threads.write', label: 'Reply in review threads', hint: 'Comment and resolve discussions' },
  { value: 'work_items.read', label: 'Read work items', hint: 'Azure Boards tasks and comments' },
  { value: 'work_items.write', label: 'Edit work items', hint: 'Create, update and comment' },
];

const DEFAULT_CAPABILITIES = CAPABILITIES.map((c) => c.value);

export const AzureDevopsConnectModal = ({ opened, onClose, basePath, azureDevops }: Props) => {
  const installations = useMemo(() => azureDevops.installations ?? [], [azureDevops.installations]);
  const patAvailable = !!azureDevops.patModeEnabled;

  const [authMode, setAuthMode] = useState<'service_principal' | 'pat'>('service_principal');
  const [installationId, setInstallationId] = useState<string | null>(installations[0]?.id?.toString() ?? null);
  const [projectId, setProjectId] = useState<string | null>(null);
  const [organizationSlug, setOrganizationSlug] = useState('');
  const [patProjectId, setPatProjectId] = useState('');
  const [pat, setPat] = useState('');
  const [capabilities, setCapabilities] = useState<string[]>(DEFAULT_CAPABILITIES);
  const [loading, setLoading] = useState(false);
  const [loadingProjects, setLoadingProjects] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const selectedInstallation = useMemo(
    () => installations.find((i) => i.id.toString() === installationId) ?? null,
    [installations, installationId],
  );
  const projects = selectedInstallation?.projects;

  // Ask the server for this organization's approved projects the first time it
  // is selected, the same partial-reload shape the repository picker uses.
  useEffect(() => {
    if (!opened || !installationId || projects !== undefined) return;

    setLoadingProjects(true);
    router.reload({
      data: { azure_devops_installation_id: installationId },
      only: ['azure_devops'],
      preserveUrl: true,
      onFinish: () => setLoadingProjects(false),
    });
  }, [opened, installationId, projects]);

  const reset = useCallback(() => {
    setAuthMode('service_principal');
    setProjectId(null);
    setOrganizationSlug('');
    setPatProjectId('');
    setPat('');
    setCapabilities(DEFAULT_CAPABILITIES);
    setError(null);
  }, []);

  const close = useCallback(() => {
    onClose();
    reset();
  }, [onClose, reset]);

  const submit = useCallback(() => {
    // Inertia's RequestPayload does not accept an index-signature object, so the
    // payload is typed as the record shape it actually is.
    const payload: Record<string, string | string[]> = {
      provider: 'azure_devops',
      authMode,
      enabledCapabilities: capabilities,
    };

    if (authMode === 'service_principal') {
      if (!installationId || !projectId) return;
      payload.azureDevopsInstallationId = installationId;
      payload.azureProjectId = projectId;
    } else {
      if (!organizationSlug.trim() || !patProjectId.trim() || !pat.trim()) return;
      payload.organizationSlug = organizationSlug.trim();
      payload.azureProjectId = patProjectId.trim();
      payload.personalAccessToken = pat.trim();
    }

    setError(null);
    setLoading(true);
    router.post(basePath, payload, {
      preserveScroll: true,
      onSuccess: () => {
        // Cleared on the way out as well as on success: the token must not
        // survive in component state after the request leaves.
        close();
      },
      onError: (errors) => {
        const message = typeof errors === 'object' && errors ? Object.values(errors).join(' ') : '';
        setError(message || 'Failed to connect Azure DevOps');
        notifications.show({ message: 'Failed to connect Azure DevOps', color: 'red' });
      },
      onFinish: () => {
        setLoading(false);
        setPat('');
      },
    });
  }, [authMode, basePath, capabilities, close, installationId, organizationSlug, pat, patProjectId, projectId]);

  const canSubmit =
    authMode === 'service_principal'
      ? !!installationId && !!projectId
      : !!organizationSlug.trim() && !!patProjectId.trim() && !!pat.trim();

  return (
    <Modal opened={opened} onClose={close} title="Connect Azure DevOps" centered size="lg">
      <Stack gap="md">
        {installations.length === 0 && authMode === 'service_principal' && (
          <Alert color="yellow" icon={<IconAlertCircle size={16} />} title="No approved organization yet">
            <Text size="sm">
              Azure DevOps access is approved per organization before a project can connect to it. Your Entra
              administrator provisions a service principal for Aixle&apos;s application in your tenant, an Azure DevOps
              administrator adds it to the organization with at least a Basic access level, and an Aixle operator
              records the approval. Ask your operator to set that up, then come back here.
            </Text>
          </Alert>
        )}

        {authMode === 'service_principal' ? (
          <>
            <Select
              label="Azure organization"
              description="Organizations your company has been approved for"
              placeholder="Select an organization"
              data={installations.map((i) => ({ value: i.id.toString(), label: i.organizationSlug }))}
              value={installationId}
              onChange={(value) => {
                setInstallationId(value);
                setProjectId(null);
              }}
              disabled={installations.length === 0}
              // Mantine deselects on a second click by default, which here would
              // silently disable the project field and leave the form dead.
              allowDeselect={false}
            />
            <Select
              label="Azure project"
              description="Only projects inside this organization's approved scope are listed. The selection cannot be changed later — connect again to work against a different project."
              placeholder={
                loadingProjects
                  ? 'Loading projects...'
                  : selectedInstallation
                    ? 'Select a project'
                    : 'Select an organization first'
              }
              data={(projects ?? []).map((p) => ({ value: p.id, label: p.name }))}
              value={projectId}
              onChange={setProjectId}
              disabled={!selectedInstallation || loadingProjects}
              allowDeselect={false}
              searchable
            />
          </>
        ) : (
          <>
            <Alert color="orange" icon={<IconAlertCircle size={16} />} title="This acts as you, not as Aixle">
              <Text size="sm">
                A personal access token carries its owner&apos;s own Azure permissions, and pull requests and comments
                are attributed to that person. It is meant for a pilot; the service principal is the production mode.
              </Text>
            </Alert>
            <TextInput
              label="Organization"
              description="The name in https://dev.azure.com/<organization>"
              placeholder="contoso"
              value={organizationSlug}
              onChange={(e) => setOrganizationSlug(e.currentTarget.value)}
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
          </Alert>
        )}

        <Group justify="space-between">
          {patAvailable ? (
            <Button
              variant="subtle"
              size="compact-sm"
              onClick={() => {
                setAuthMode(authMode === 'pat' ? 'service_principal' : 'pat');
                setError(null);
              }}
            >
              {authMode === 'pat' ? 'Use the approved organization instead' : 'Use a personal access token instead'}
            </Button>
          ) : (
            <span />
          )}
          <Group gap="sm">
            <Button variant="default" onClick={close}>
              Cancel
            </Button>
            <Button onClick={submit} loading={loading} disabled={!canSubmit}>
              Connect
            </Button>
          </Group>
        </Group>
      </Stack>
    </Modal>
  );
};
