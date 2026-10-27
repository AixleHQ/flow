import { router } from '@inertiajs/react';
import {
  Alert,
  Button,
  Code,
  Group,
  Modal,
  MultiSelect,
  PasswordInput,
  Radio,
  SegmentedControl,
  Stack,
  Text,
  TextInput,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconAlertCircle, IconCheck } from '@tabler/icons-react';
import { useCallback, useEffect, useState } from 'react';

import { useConfirmClose } from 'shared/lib/hooks/useConfirmClose';

import { AzureDevopsFederatedForm, type AzureDevopsFederation } from './AzureDevopsFederatedForm';
import { type AzureDevopsProject, capabilitiesChanged, DEFAULT_CAPABILITIES, postJson } from './azureDevopsShared';
import { CapabilityPicker } from './CapabilityPicker';

export type { AzureDevopsProject } from './azureDevopsShared';
export type { AzureDevopsFederation } from './AzureDevopsFederatedForm';

export interface AzureDevopsProps {
  enabled: boolean;
  patModeEnabled?: boolean;
  /** False when only the customer's own Entra app can be used. Absent means the shared app is available. */
  sharedAppEnabled?: boolean;
  /** Not a secret: it is what a customer runs `az ad sp create --id` with. */
  clientId?: string | null;
  /** Present when this deployment can act as the issuer for a customer's own Entra app. */
  federation?: AzureDevopsFederation | null;
}

/** A Microsoft sign-in the server holds, to resume the dialog with after the redirect back. */
export interface AzureSignIn {
  handle: string;
  organization: string;
}

interface Props {
  opened: boolean;
  onClose: () => void;
  basePath: string;
  azureDevops: AzureDevopsProps;
  signIn?: AzureSignIn | null;
}

type Proof = 'sign_in' | 'admin_pat';
type AuthMode = 'service_principal' | 'federated' | 'pat';

interface Inspection {
  organization: string;
  tenantId: string;
  identity: string | null;
  alreadyBound: boolean;
  projects: AzureDevopsProject[];
}

export const AzureDevopsConnectModal = ({ opened, onClose, basePath, azureDevops, signIn }: Props) => {
  const patAvailable = !!azureDevops.patModeEnabled;
  const federationAvailable = !!azureDevops.federation;
  const sharedAppAvailable = azureDevops.sharedAppEnabled !== false;
  const initialMode: AuthMode = sharedAppAvailable || !federationAvailable ? 'service_principal' : 'federated';

  const [authMode, setAuthMode] = useState<AuthMode>(initialMode);
  const [federatedDirty, setFederatedDirty] = useState(false);
  const [proof, setProof] = useState<Proof>('sign_in');
  const [organization, setOrganization] = useState('');
  const [adminPat, setAdminPat] = useState('');
  const [inspection, setInspection] = useState<Inspection | null>(null);
  const [projectIds, setProjectIds] = useState<string[]>([]);

  const [patProjectId, setPatProjectId] = useState('');
  const [pat, setPat] = useState('');

  const [capabilities, setCapabilities] = useState<string[]>(DEFAULT_CAPABILITIES);
  const [verifying, setVerifying] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const reset = useCallback(() => {
    setAuthMode(initialMode);
    setFederatedDirty(false);
    setProof('sign_in');
    setOrganization('');
    setAdminPat('');
    setInspection(null);
    setProjectIds([]);
    setPatProjectId('');
    setPat('');
    setCapabilities(DEFAULT_CAPABILITIES);
    setError(null);
  }, [initialMode]);

  const close = useCallback(() => {
    onClose();
    reset();
  }, [onClose, reset]);

  // A resumed dialog is already carrying a Microsoft sign-in, and closing drops it: getting it
  // back means signing in again.
  const dirty =
    !!signIn ||
    organization !== '' ||
    adminPat !== '' ||
    projectIds.length > 0 ||
    patProjectId !== '' ||
    pat !== '' ||
    federatedDirty ||
    capabilitiesChanged(capabilities);
  const requestClose = useConfirmClose(dirty, close);

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
        ...(signIn ? { sign_in: signIn.handle } : { personal_access_token: adminPat.trim() }),
      })) as Inspection;
      setInspection(result);
      // Nothing is preselected: a connection reaches what someone chose,
      // not what happened to come back first.
      setProjectIds([]);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not verify the organization');
    } finally {
      setVerifying(false);
    }
  }, [adminPat, basePath, organization, signIn]);

  // Back from Microsoft: the sign-in is held on the server, so verify with it
  // straight away instead of asking for anything again.
  useEffect(() => {
    if (!opened || !signIn) return;
    setOrganization(signIn.organization);
    setProof('sign_in');
  }, [opened, signIn]);

  useEffect(() => {
    if (opened && signIn && organization === signIn.organization && !inspection && !verifying && !error) void verify();
  }, [error, inspection, opened, organization, signIn, verify, verifying]);

  // Step two: entitle the application in the organization, record the binding,
  // then create the project connection on top of it.
  const connect = useCallback(async () => {
    if (!inspection || projectIds.length === 0) return;
    setError(null);
    setLoading(true);
    try {
      const bound = (await postJson(`${basePath}/azure_devops_connect`, {
        organization: inspection.organization,
        ...(signIn ? { sign_in: signIn.handle } : { personal_access_token: adminPat.trim() }),
        project_ids: projectIds,
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
          azureProjectIds: projectIds,
          azureProjectNames: Object.fromEntries(
            inspection.projects.filter((p) => projectIds.includes(p.id)).map((p) => [p.id, p.name]),
          ),
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
  }, [adminPat, basePath, capabilities, close, inspection, projectIds, signIn]);

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
        azureProjectIds: patProjectId
          .split(',')
          .map((id) => id.trim())
          .filter(Boolean),
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

  // Choosing between Aixle's own Microsoft app and the customer's. The personal
  // access token path is a separate, explicitly labelled fallback below.
  const modeSwitch =
    federationAvailable && sharedAppAvailable && authMode !== 'pat' ? (
      <SegmentedControl
        fullWidth
        value={authMode}
        onChange={(value) => {
          setAuthMode(value as AuthMode);
          setError(null);
        }}
        data={[
          { value: 'service_principal', label: 'Aixle’s Microsoft app' },
          { value: 'federated', label: 'Your own Entra app' },
        ]}
      />
    ) : null;

  if (authMode === 'federated' && azureDevops.federation) {
    return (
      <Modal opened={opened} onClose={requestClose} title="Connect Azure DevOps" centered size="lg">
        <Stack gap="md">
          {modeSwitch}
          <AzureDevopsFederatedForm
            basePath={basePath}
            federation={azureDevops.federation}
            capabilities={capabilities}
            onCapabilitiesChange={setCapabilities}
            onDirtyChange={setFederatedDirty}
            onCancel={requestClose}
            onConnected={close}
          />
          {patAvailable && (
            <Group>
              <Button
                variant="subtle"
                size="compact-sm"
                onClick={() => {
                  setAuthMode('pat');
                  setError(null);
                }}
              >
                Connect as yourself with a personal access token instead
              </Button>
            </Group>
          )}
        </Stack>
      </Modal>
    );
  }

  return (
    <Modal opened={opened} onClose={requestClose} title="Connect Azure DevOps" centered size="lg">
      <Stack gap="md">
        {modeSwitch}
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

            {!inspection && !signIn && (
              <Radio.Group value={proof} onChange={(value) => setProof(value as Proof)}>
                <Stack gap="sm">
                  <Radio
                    value="sign_in"
                    label="I administer the organization and can sign in with Microsoft (Recommended)"
                    description="Aixle gets its own identity in your organization: a service principal with its own access, never a person's token. Microsoft asks you to approve Aixle once, and that approval also adds Aixle's application to your directory."
                  />
                  <Radio
                    value="admin_pat"
                    label="I'll prove it with an administrator personal access token"
                    description="For a directory where you cannot approve applications yourself. The token is used once and never stored, and the connection still runs on Aixle's own identity."
                  />
                </Stack>
              </Radio.Group>
            )}

            {!inspection && proof === 'sign_in' && !signIn && (
              <>
                <Text size="sm" c="dimmed">
                  You will be sent to Microsoft to sign in as an administrator of this organization, then returned here
                  to choose its projects.
                </Text>
                <Group justify="space-between">
                  <Button
                    variant="subtle"
                    size="compact-sm"
                    onClick={verify}
                    loading={verifying}
                    disabled={!organization.trim()}
                  >
                    Already connected for your company? Continue without signing in
                  </Button>
                  <Button
                    component="a"
                    href={`${basePath}/azure_devops_sign_in?organization=${encodeURIComponent(organization.trim())}`}
                    disabled={!organization.trim()}
                  >
                    Sign in with Microsoft
                  </Button>
                </Group>
              </>
            )}

            {!inspection && signIn && verifying && <Text size="sm">Checking your Microsoft sign-in…</Text>}

            {!inspection && proof === 'admin_pat' && azureDevops.clientId && (
              // Shown BEFORE verifying, not only after it fails: this is the one
              // step that happens outside Flow, in a different portal, and
              // usually by a different person. Finding out about it from an
              // error means going away and coming back.
              <Alert color="gray" variant="light" title="One step in your Entra directory first">
                <Text size="sm">
                  A directory administrator runs this once. Nothing is consented to and no permission is granted — it
                  only makes Aixle&apos;s application nameable in your organization.
                </Text>
                <Code block mt={8}>
                  az ad sp create --id {azureDevops.clientId}
                </Code>
              </Alert>
            )}

            {!inspection && proof === 'admin_pat' && (
              <>
                <PasswordInput
                  label="Administrator personal access token"
                  description="Used once, in this request: it proves the organization is yours, adds Aixle to it, and lets Aixle manage its own Service Hooks. It is never stored, and the connection runs on Aixle’s own identity afterwards. Needs three scopes: Member Entitlement Management (read & write), Project and team (read), and Security (manage). Leave empty if your company has already connected this organization — unless you want to reach an Azure project it has not approved yet, which needs a token again."
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
                      ? `Your company has already connected this organization${inspection.identity ? `, and ${inspection.identity} can approve more projects now` : ', so no sign-in was needed'}.`
                      : `Verified${inspection.identity ? ` as ${inspection.identity}` : ''}. Aixle will be added to this organization with a Basic access level.`}
                  </Text>
                </Alert>
                <MultiSelect
                  label="Azure projects"
                  description="Everything this connection can reach. Repositories, work items and builds outside these projects stay out of reach, and the list cannot be changed later — connect again to cover others."
                  placeholder={projectIds.length === 0 ? 'Select one or more projects' : undefined}
                  data={inspection.projects.map((p) => ({ value: p.id, label: p.name }))}
                  value={projectIds}
                  onChange={setProjectIds}
                  searchable
                  clearable
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
              label="Azure project IDs"
              description="The project GUIDs, comma separated, from Project settings → Overview"
              placeholder="00000000-0000-0000-0000-000000000000, 11111111-..."
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

        <CapabilityPicker value={capabilities} onChange={setCapabilities} />

        {error && (
          <Alert color="red" icon={<IconAlertCircle size={16} />}>
            {error}
            {missingPrincipal && (
              <Text size="sm" mt="xs">
                Aixle&apos;s application has not been added to your Microsoft Entra directory yet. A directory
                administrator runs this once — nothing is consented to and no permission is granted, it only makes the
                application nameable in your organization:
                <Code block mt={6}>
                  az ad sp create --id {azureDevops.clientId ?? '<client id>'}
                </Code>
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
                setAuthMode(authMode === 'pat' ? initialMode : 'pat');
                setInspection(null);
                setError(null);
              }}
            >
              {authMode === 'pat'
                ? initialMode === 'federated'
                  ? 'Use your own Entra app instead'
                  : 'Use Aixle’s own identity instead'
                : 'Connect as yourself with a personal access token instead'}
            </Button>
          ) : (
            <span />
          )}
          <Group gap="sm">
            <Button variant="default" onClick={requestClose}>
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
              <Button onClick={connect} loading={loading} disabled={!inspection || projectIds.length === 0}>
                Connect
              </Button>
            )}
          </Group>
        </Group>
      </Stack>
    </Modal>
  );
};
