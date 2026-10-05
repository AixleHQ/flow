import { router, usePage } from '@inertiajs/react';
import {
  ActionIcon,
  Anchor,
  Badge,
  Box,
  Button,
  CopyButton,
  Group,
  Menu,
  Modal,
  NumberInput,
  PasswordInput,
  SegmentedControl,
  Stack,
  Table,
  Text,
  TextInput,
  Tooltip,
  UnstyledButton,
} from '@mantine/core';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import {
  IconBrandAzure,
  IconBrandGithub,
  IconBrandJira,
  IconBrandSlack,
  IconBrandTeams,
  IconCheck,
  IconChevronDown,
  IconChevronRight,
  IconCopy,
  IconDownload,
  IconKey,
  IconLayoutKanban,
  IconLink,
  IconPencil,
  IconPlus,
  IconRefresh,
  IconSearch,
  IconSettings,
  IconTicket,
  IconTrash,
  IconWebhook,
} from '@tabler/icons-react';
import { useCallback, useEffect, useMemo, useState } from 'react';

import type { Integration } from '@/types/generated';

import { formatDateMedium } from 'shared/lib/formatDate';
import { useConfirmClose } from 'shared/lib/hooks/useConfirmClose';
import { useProjectPermissions } from 'shared/lib/hooks/useProjectPermissions';
import { isValidHttpUrl } from 'shared/lib/urlValidation';
import { EmptyState } from 'shared/ui/EmptyState';
import { PageHeader } from 'shared/ui/PageHeader';
import { ResourceCount, ResourceTableShell, ResourceTh } from 'shared/ui/ResourceTable';
import { StatusBadge } from 'shared/ui/StatusBadge';

import { AzureDevopsConnectModal, type AzureDevopsProps, type AzureSignIn } from './AzureDevopsConnectModal';
import { GithubConnectModal, type GithubProps } from './GithubConnectModal';
import { GithubProjectsModal } from './GithubProjectsModal';
import { JiraConnectModal, JiraProjectsModal, type JiraProps, JiraWebhookModal } from './JiraConnectModal';
import { LinearConnectModal, type LinearProps, LinearTeamsModal } from './LinearConnectModal';
import {
  YoutrackConnectModal,
  YoutrackProjectsModal,
  type YoutrackProps,
  YoutrackWebhookModal,
} from './YoutrackConnectModal';
import { TeamsApprovalModal } from './TeamsApprovalModal';

export type { AzureDevopsProps } from './AzureDevopsConnectModal';
export type { GithubProps } from './GithubConnectModal';
export type { JiraProps } from './JiraConnectModal';
export type { LinearProps } from './LinearConnectModal';
export type { YoutrackProps } from './YoutrackConnectModal';

export interface SlackProps {
  /** False on a deployment with no Slack app (SLACK_CLIENT_ID / SLACK_CLIENT_SECRET unset). */
  enabled: boolean;
}

export interface TeamsProps {
  /** False on a deployment with no Teams bot (no bot app, credential or home tenant configured). */
  enabled: boolean;
}

interface IntegrationsContentProps {
  integrations: Integration[];
  basePath: string;
  title: string;
  // Absent on the company page and whenever the deployment has Azure DevOps
  // switched off, which is what hides the connect entry entirely.
  azureDevops?: AzureDevopsProps;
  // Absent on the company page. `appConfigured: false` is a deployment with no
  // GitHub App — the connect dialog then opens on the token path.
  github?: GithubProps;
  // Absent on the company page: Jira connects to a project.
  jira?: JiraProps;
  // Absent on the company page: Linear connects to a project.
  linear?: LinearProps;
  // Absent on the company page: YouTrack connects to a project.
  youtrack?: YoutrackProps;
  // Absent on the company page.
  slack?: SlackProps;
  // Absent on the company page.
  teams?: TeamsProps;
}

const GitlabIcon = () => <img src="/images/gitlab.svg" alt="GitLab" width={20} height={20} />;
const CoderIcon = ({ size = 20 }: { size?: number } = {}) => (
  <img src="/images/coder.svg" alt="Coder" width={size} height={size} />
);

const ProviderIcon = ({ provider, size = 18 }: { provider: string; size?: number }) => {
  if (provider === 'github') return <IconBrandGithub size={size} />;
  if (provider === 'gitlab') return <img src="/images/gitlab.svg" alt="GitLab" width={size} height={size} />;
  if (provider === 'coder') return <img src="/images/coder.svg" alt="Coder" width={size} height={size} />;
  if (provider === 'slack') return <IconBrandSlack size={size} />;
  if (provider === 'teams') return <IconBrandTeams size={size} />;
  if (provider === 'azure_devops') return <IconBrandAzure size={size} />;
  if (provider === 'jira') return <IconBrandJira size={size} />;
  if (provider === 'linear') return <IconLayoutKanban size={size} />;
  if (provider === 'youtrack') return <IconTicket size={size} />;
  return <IconLink size={size} />;
};

const PROVIDER_LABELS: Record<string, string> = {
  github: 'GitHub',
  gitlab: 'GitLab',
  coder: 'Coder',
  slack: 'Slack',
  teams: 'Microsoft Teams',
  azure_devops: 'Azure DevOps',
  jira: 'Jira',
  linear: 'Linear',
  youtrack: 'YouTrack',
};

const SCOPE_COLORS: Record<string, string> = {
  company: 'gray',
  project: 'green',
};

// Mirrors the server-side fallback in Coder::LockService#ttl_minutes.
const DEFAULT_CODER_LOCK_TTL = 120;

const TOKEN_PROVIDERS = new Set(['gitlab', 'coder']);

const errorMessage = (errors: unknown, fallback: string) =>
  (typeof errors === 'object' && errors ? Object.values(errors).join(' ') : '') || fallback;

export const IntegrationsContent = ({
  integrations,
  basePath,
  title,
  azureDevops,
  github,
  jira,
  linear,
  youtrack,
  slack,
  teams,
}: IntegrationsContentProps) => {
  const { canExecute, canManageCompany } = useProjectPermissions();
  const isProjectContext = basePath.includes('projects');
  const [search, setSearch] = useState('');
  const [scopeFilter, setScopeFilter] = useState('all');
  const [connectMenuOpened, setConnectMenuOpened] = useState(false);

  const [azureOpen, setAzureOpen] = useState(false);
  const [azureSignIn, setAzureSignIn] = useState<AzureSignIn | null>(null);
  const azureAvailable = !!azureDevops?.enabled;

  // Back from "Sign in with Microsoft": the server holds the sign-in, and the
  // dialog picks up where it left off.
  useEffect(() => {
    const query = new URLSearchParams(window.location.search);
    const handle = query.get('azure_setup');
    const organization = query.get('azure_organization');
    if (!handle || !organization) return;
    setAzureSignIn({ handle, organization });
    setAzureOpen(true);
    query.delete('azure_setup');
    query.delete('azure_organization');
    const rest = query.toString();
    window.history.replaceState(window.history.state, '', `${window.location.pathname}${rest ? `?${rest}` : ''}`);
  }, []);

  const [githubOpen, setGithubOpen] = useState(false);
  const [githubProjectsTarget, setGithubProjectsTarget] = useState<Integration | null>(null);

  const [jiraOpen, setJiraOpen] = useState(false);
  const [jiraProjectsTarget, setJiraProjectsTarget] = useState<Integration | null>(null);
  const [jiraWebhookTarget, setJiraWebhookTarget] = useState<Integration | null>(null);
  const jiraAvailable = isProjectContext && !!jira;
  const slackAvailable = isProjectContext && !!slack?.enabled;
  const teamsAvailable = isProjectContext && !!teams?.enabled;

  const [linearOpen, setLinearOpen] = useState(false);
  const [linearTeamsTarget, setLinearTeamsTarget] = useState<Integration | null>(null);
  const linearAvailable = isProjectContext && !!linear;

  const [youtrackOpen, setYoutrackOpen] = useState(false);
  const [youtrackProjectsTarget, setYoutrackProjectsTarget] = useState<Integration | null>(null);
  const [youtrackWebhookTarget, setYoutrackWebhookTarget] = useState<Integration | null>(null);
  const youtrackAvailable = isProjectContext && !!youtrack?.enabled;

  // The Atlassian and Linear apps' callbacks land here with the connection still to finish.
  useEffect(() => {
    const query = new URLSearchParams(window.location.search);
    const pending = (param: string, provider: string) => {
      const id = Number(query.get(param));
      return id ? integrations.find((i) => i.id === id && i.provider === provider) : undefined;
    };
    const jiraPending = pending('jira_setup', 'jira');
    if (jiraPending) setJiraProjectsTarget(jiraPending);
    const linearPending = pending('linear_setup', 'linear');
    if (linearPending) setLinearTeamsTarget(linearPending);
  }, [integrations]);

  const [gitlabOpen, setGitlabOpen] = useState(false);
  const [gitlabPat, setGitlabPat] = useState('');
  const [gitlabLoading, setGitlabLoading] = useState(false);
  const [gitlabError, setGitlabError] = useState<string | null>(null);

  const closeGitlabModal = useCallback(() => {
    setGitlabOpen(false);
    setGitlabPat('');
    setGitlabError(null);
  }, []);
  const requestCloseGitlab = useConfirmClose(gitlabPat !== '', closeGitlabModal);

  const [tokenTarget, setTokenTarget] = useState<Integration | null>(null);
  const [replacementToken, setReplacementToken] = useState('');
  const [tokenLoading, setTokenLoading] = useState(false);
  const [tokenError, setTokenError] = useState<string | null>(null);

  const closeTokenModal = useCallback(() => {
    setTokenTarget(null);
    setReplacementToken('');
    setTokenError(null);
  }, []);
  const requestCloseToken = useConfirmClose(replacementToken !== '', closeTokenModal);

  const [coderOpen, setCoderOpen] = useState(false);
  const [coderUrl, setCoderUrl] = useState('');
  const [coderToken, setCoderToken] = useState('');
  const [coderDefaultTemplate, setCoderDefaultTemplate] = useState('');
  const [coderMachinePrefix, setCoderMachinePrefix] = useState('');
  const [coderLockTtlMinutes, setCoderLockTtlMinutes] = useState<number | string>(DEFAULT_CODER_LOCK_TTL);
  const [coderAdvancedOpen, setCoderAdvancedOpen] = useState(false);
  const [coderLoading, setCoderLoading] = useState(false);
  const [coderError, setCoderError] = useState<string | null>(null);

  const [coderEditTarget, setCoderEditTarget] = useState<Integration | null>(null);
  const [coderEditTemplate, setCoderEditTemplate] = useState('');
  const [coderEditPrefix, setCoderEditPrefix] = useState('');
  const [coderEditTtl, setCoderEditTtl] = useState<number | string>(DEFAULT_CODER_LOCK_TTL);
  const [coderEditLoading, setCoderEditLoading] = useState(false);

  const resetCoderForm = useCallback(() => {
    setCoderUrl('');
    setCoderToken('');
    setCoderDefaultTemplate('');
    setCoderMachinePrefix('');
    setCoderLockTtlMinutes(DEFAULT_CODER_LOCK_TTL);
    setCoderAdvancedOpen(false);
    setCoderError(null);
  }, []);

  const closeCoderModal = useCallback(() => {
    setCoderOpen(false);
    resetCoderForm();
  }, [resetCoderForm]);
  const requestCloseCoder = useConfirmClose(
    coderUrl !== '' ||
      coderToken !== '' ||
      coderDefaultTemplate !== '' ||
      coderMachinePrefix !== '' ||
      coderLockTtlMinutes !== DEFAULT_CODER_LOCK_TTL,
    closeCoderModal,
  );

  const closeCoderSettings = useCallback(() => setCoderEditTarget(null), []);
  const requestCloseCoderSettings = useConfirmClose(
    !!coderEditTarget &&
      (coderEditTemplate !== (coderEditTarget.coderDefaultTemplate ?? '') ||
        coderEditPrefix !== (coderEditTarget.coderMachinePrefix ?? '') ||
        coderEditTtl !== (coderEditTarget.coderLockTtlMinutes ?? DEFAULT_CODER_LOCK_TTL)),
    closeCoderSettings,
  );

  const filtered = useMemo(() => {
    let result = integrations;

    if (search.trim()) {
      const q = search.toLowerCase();
      result = result.filter((i) => i.name.toLowerCase().includes(q));
    }

    if (scopeFilter !== 'all') {
      result = result.filter((i) => i.scopeIndicator === scopeFilter);
    }

    return result;
  }, [integrations, search, scopeFilter]);

  const hasFilters = !!search || scopeFilter !== 'all';

  const handleDelete = useCallback(
    (integration: Integration) => {
      modals.openConfirmModal({
        title: 'Remove Integration',
        children: (
          <Stack gap="xs">
            <Text size="sm">
              Are you sure you want to remove <b>{integration.name}</b>? This will also disconnect all repositories
              linked through this integration.
            </Text>
            {integration.githubAuthMode === 'app' && (
              <Text size="sm">
                The GitHub App stays installed on GitHub, where other projects may still use it.{' '}
                {integration.githubUrl ? (
                  <Anchor href={integration.githubUrl} target="_blank" size="sm">
                    Uninstall it on GitHub
                  </Anchor>
                ) : (
                  'Uninstall it on GitHub'
                )}{' '}
                if nothing else needs it.
              </Text>
            )}
          </Stack>
        ),
        labels: { confirm: 'Remove', cancel: 'Cancel' },
        confirmProps: { color: 'red' },
        onConfirm: () => {
          router.delete(`${basePath}/${integration.id}`, {
            preserveScroll: true,
            onSuccess: () => notifications.show({ message: 'Integration removed', color: 'green' }),
            onError: () => notifications.show({ message: 'Failed to remove integration', color: 'red' }),
          });
        },
      });
    },
    [basePath],
  );

  // Both GitHub paths live in the dialog: the App install (which redirects to
  // GitHub) and a pasted personal access token. Opening it used to go straight
  // to the install, which dead-ended anyone who cannot install an app.
  const handleConnectGithub = useCallback(() => setGithubOpen(true), []);

  const handleConnectGitlab = useCallback(() => {
    if (!gitlabPat.trim()) return;
    setGitlabError(null);
    setGitlabLoading(true);

    router.post(
      basePath,
      {
        provider: 'gitlab',
        personalAccessToken: gitlabPat.trim(),
      },
      {
        preserveScroll: true,
        onSuccess: closeGitlabModal,
        onError: (errors) => setGitlabError(errorMessage(errors, 'Failed to connect GitLab')),
        onFinish: () => setGitlabLoading(false),
      },
    );
  }, [basePath, closeGitlabModal, gitlabPat]);

  const handleReplaceToken = useCallback(() => {
    const token = replacementToken.trim();
    if (!tokenTarget || !token) return;
    setTokenError(null);
    setTokenLoading(true);

    router.patch(
      `${basePath}/${tokenTarget.id}`,
      tokenTarget.provider === 'coder' ? { sessionToken: token } : { personalAccessToken: token },
      {
        preserveScroll: true,
        onSuccess: closeTokenModal,
        onError: (errors) => setTokenError(errorMessage(errors, 'Failed to replace the token')),
        onFinish: () => setTokenLoading(false),
      },
    );
  }, [basePath, closeTokenModal, replacementToken, tokenTarget]);

  const handleConnectCoder = useCallback(() => {
    const trimmedUrl = coderUrl.trim();
    const trimmedToken = coderToken.trim();
    if (!trimmedUrl || !trimmedToken) return;
    if (!isValidHttpUrl(trimmedUrl)) {
      setCoderError('Coder URL must be a valid http or https URL');
      return;
    }

    setCoderError(null);
    setCoderLoading(true);

    const ttl = typeof coderLockTtlMinutes === 'number' ? coderLockTtlMinutes : Number(coderLockTtlMinutes);
    const payload: Record<string, string | number> = {
      provider: 'coder',
      coderUrl: trimmedUrl,
      sessionToken: trimmedToken,
    };
    if (coderDefaultTemplate.trim()) payload.defaultTemplate = coderDefaultTemplate.trim();
    if (coderMachinePrefix.trim()) payload.machinePrefix = coderMachinePrefix.trim();
    if (!Number.isNaN(ttl) && ttl > 0) payload.lockTtlMinutes = ttl;

    router.post(basePath, payload, {
      preserveScroll: true,
      onSuccess: () => {
        closeCoderModal();
      },
      onError: (errors) => setCoderError(errorMessage(errors, 'Failed to connect Coder')),
      onFinish: () => setCoderLoading(false),
    });
  }, [basePath, closeCoderModal, coderDefaultTemplate, coderLockTtlMinutes, coderMachinePrefix, coderToken, coderUrl]);

  const openCoderSettings = useCallback((integration: Integration) => {
    setCoderEditTarget(integration);
    setCoderEditTemplate(integration.coderDefaultTemplate ?? '');
    setCoderEditPrefix(integration.coderMachinePrefix ?? '');
    setCoderEditTtl(integration.coderLockTtlMinutes ?? DEFAULT_CODER_LOCK_TTL);
  }, []);

  const handleSaveCoderSettings = useCallback(() => {
    if (!coderEditTarget) return;
    const ttl = typeof coderEditTtl === 'number' ? coderEditTtl : Number(coderEditTtl);
    if (Number.isNaN(ttl) || ttl <= 0) return;

    setCoderEditLoading(true);
    // Template and prefix go out even when empty — a blank value clears the
    // setting, which is how you stop the allocator from creating machines.
    router.patch(
      `${basePath}/${coderEditTarget.id}`,
      { defaultTemplate: coderEditTemplate.trim(), machinePrefix: coderEditPrefix.trim(), lockTtlMinutes: ttl },
      {
        preserveScroll: true,
        onSuccess: () => setCoderEditTarget(null),
        onError: () => notifications.show({ message: 'Failed to save Coder settings', color: 'red' }),
        onFinish: () => setCoderEditLoading(false),
      },
    );
  }, [basePath, coderEditPrefix, coderEditTarget, coderEditTemplate, coderEditTtl]);

  // Re-verify an Azure or Jira connection. "Test" and "repair" are the same
  // operation: the integration id and what hangs off it are kept either way, and
  // a failed check never replaces a working credential.
  const handleTestConnection = useCallback(
    (integration: Integration) => {
      router.post(
        `${basePath}/${integration.id}/test_connection`,
        {},
        {
          preserveScroll: true,
          onError: () => notifications.show({ message: 'Connection test failed', color: 'red' }),
        },
      );
    },
    [basePath],
  );

  // Slack connects via OAuth: redirect to the project-scoped start action, which
  // bounces to Slack's consent screen. The install binds to this project.
  const handleConnectSlack = useCallback(() => {
    window.location.href = `${basePath}/slack_oauth_start`;
  }, [basePath]);

  // Teams is approved by a Microsoft 365 administrator, who may not have an
  // Aixle account: the server creates a pending connection and hands back, once,
  // the link that person opens.
  const handleConnectTeams = useCallback(() => {
    router.post(`${basePath}/teams_connect`, {}, { preserveScroll: true });
  }, [basePath]);
  const { flash } = usePage<{ flash?: Record<string, unknown> }>().props;
  const teamsApprovalUrl = typeof flash?.teamsApprovalUrl === 'string' ? flash.teamsApprovalUrl : null;
  const [dismissedApprovalUrl, setDismissedApprovalUrl] = useState<string | null>(null);

  return (
    <Box>
      <PageHeader
        title={title}
        subtitle={
          isProjectContext
            ? 'Connect GitHub, GitLab, Coder or Slack for this project, or use company-wide integrations'
            : 'Connect external services to your company'
        }
        actions={
          canExecute && (
            <Menu position="bottom-end" withArrow opened={connectMenuOpened} onChange={setConnectMenuOpened}>
              <Menu.Target>
                <Button
                  leftSection={<IconPlus size={16} />}
                  rightSection={
                    <IconChevronDown
                      size={14}
                      style={{
                        transition: 'transform 150ms ease',
                        transform: connectMenuOpened ? 'rotate(180deg)' : 'none',
                      }}
                    />
                  }
                >
                  Connect
                </Button>
              </Menu.Target>
              <Menu.Dropdown>
                <Menu.Item leftSection={<IconBrandGithub size={16} />} onClick={handleConnectGithub}>
                  GitHub
                </Menu.Item>
                <Menu.Item leftSection={<GitlabIcon />} onClick={() => setGitlabOpen(true)}>
                  GitLab
                </Menu.Item>
                <Menu.Item leftSection={<CoderIcon size={16} />} onClick={() => setCoderOpen(true)}>
                  Coder
                </Menu.Item>
                {isProjectContext && azureAvailable && (
                  <Menu.Item leftSection={<IconBrandAzure size={16} />} onClick={() => setAzureOpen(true)}>
                    Azure DevOps
                  </Menu.Item>
                )}
                {jiraAvailable && (
                  <Menu.Item leftSection={<IconBrandJira size={16} />} onClick={() => setJiraOpen(true)}>
                    Jira
                  </Menu.Item>
                )}
                {linearAvailable && (
                  <Menu.Item leftSection={<IconLayoutKanban size={16} />} onClick={() => setLinearOpen(true)}>
                    Linear
                  </Menu.Item>
                )}
                {youtrackAvailable && (
                  <Menu.Item leftSection={<IconTicket size={16} />} onClick={() => setYoutrackOpen(true)}>
                    YouTrack
                  </Menu.Item>
                )}
                {slackAvailable && (
                  <Menu.Item leftSection={<IconBrandSlack size={16} />} onClick={handleConnectSlack}>
                    Slack
                  </Menu.Item>
                )}
                {teamsAvailable && (
                  <Menu.Item leftSection={<IconBrandTeams size={16} />} onClick={handleConnectTeams}>
                    Microsoft Teams
                  </Menu.Item>
                )}
              </Menu.Dropdown>
            </Menu>
          )
        }
      />

      <Group gap="md" mb="lg">
        <TextInput
          placeholder="Search by name..."
          leftSection={<IconSearch size={16} />}
          value={search}
          onChange={(e) => setSearch(e.currentTarget.value)}
          maw={300}
        />
        {isProjectContext && (
          <SegmentedControl
            value={scopeFilter}
            onChange={setScopeFilter}
            data={[
              { label: 'All', value: 'all' },
              { label: 'Project', value: 'project' },
              { label: 'Company', value: 'company' },
            ]}
            size="sm"
          />
        )}
        <ResourceCount>
          {filtered.length} {filtered.length === 1 ? 'integration' : 'integrations'}
        </ResourceCount>
      </Group>

      {filtered.length === 0 ? (
        <Box
          style={{
            border: '1px solid var(--app-border-default)',
            borderRadius: 'var(--mantine-radius-md)',
            backgroundColor: 'var(--app-bg-paper)',
          }}
        >
          {hasFilters ? (
            <EmptyState
              icon={<IconLink size={22} />}
              title={
                scopeFilter !== 'all' && !search
                  ? 'No integrations in this scope.'
                  : 'No integrations match your search'
              }
            />
          ) : (
            <EmptyState
              icon={<IconLink size={22} />}
              title="No integrations connected"
              description="Connect GitHub or GitLab for repositories, Coder for workspaces, or Slack to trigger workflows from messages."
              action={
                canExecute && (
                  <Group gap="sm" justify="center" wrap="wrap">
                    <Button variant="outline" leftSection={<IconBrandGithub size={16} />} onClick={handleConnectGithub}>
                      GitHub
                    </Button>
                    <Button variant="outline" leftSection={<GitlabIcon />} onClick={() => setGitlabOpen(true)}>
                      GitLab
                    </Button>
                    <Button variant="outline" leftSection={<CoderIcon size={16} />} onClick={() => setCoderOpen(true)}>
                      Coder
                    </Button>
                    {isProjectContext && azureAvailable && (
                      <Button
                        variant="outline"
                        leftSection={<IconBrandAzure size={16} />}
                        onClick={() => setAzureOpen(true)}
                      >
                        Azure DevOps
                      </Button>
                    )}
                    {jiraAvailable && (
                      <Button
                        variant="outline"
                        leftSection={<IconBrandJira size={16} />}
                        onClick={() => setJiraOpen(true)}
                      >
                        Jira
                      </Button>
                    )}
                    {linearAvailable && (
                      <Button
                        variant="outline"
                        leftSection={<IconLayoutKanban size={16} />}
                        onClick={() => setLinearOpen(true)}
                      >
                        Linear
                      </Button>
                    )}
                    {youtrackAvailable && (
                      <Button
                        variant="outline"
                        leftSection={<IconTicket size={16} />}
                        onClick={() => setYoutrackOpen(true)}
                      >
                        YouTrack
                      </Button>
                    )}
                    {slackAvailable && (
                      <Button variant="outline" leftSection={<IconBrandSlack size={16} />} onClick={handleConnectSlack}>
                        Slack
                      </Button>
                    )}
                  </Group>
                )
              }
            />
          )}
        </Box>
      ) : (
        <ResourceTableShell>
          <Table highlightOnHover>
            <Table.Thead style={{ backgroundColor: 'var(--app-bg-deep)' }}>
              <Table.Tr>
                <ResourceTh>Name</ResourceTh>
                <ResourceTh>Provider</ResourceTh>
                {isProjectContext && <ResourceTh>Scope</ResourceTh>}
                <ResourceTh>Status</ResourceTh>
                <ResourceTh>Connected by</ResourceTh>
                <ResourceTh align="right" w={150}>
                  Actions
                </ResourceTh>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {filtered.map((integration) => {
                const readOnly = isProjectContext && integration.scopeIndicator === 'company';

                return (
                  <Table.Tr key={integration.id}>
                    <Table.Td>
                      <Group gap="sm" wrap="nowrap">
                        <Box
                          w={30}
                          h={30}
                          style={{
                            display: 'flex',
                            alignItems: 'center',
                            justifyContent: 'center',
                            backgroundColor: 'var(--app-bg-deep)',
                            borderRadius: 'var(--mantine-radius-sm)',
                            color: 'var(--app-text-secondary)',
                            flexShrink: 0,
                          }}
                        >
                          <ProviderIcon provider={integration.provider} />
                        </Box>
                        <Box style={{ minWidth: 0 }}>
                          <Text fz={14} fw={500} c="var(--app-text-primary)" truncate>
                            {integration.name}
                          </Text>
                          {integration.provider === 'slack' && integration.slackRequestUrl && (
                            <Group gap={4} wrap="nowrap">
                              <Text fz={11} c="dimmed" ff="JetBrains Mono, monospace" truncate maw={180}>
                                {integration.slackRequestUrl}
                              </Text>
                              <CopyButton value={integration.slackRequestUrl}>
                                {({ copied, copy }) => (
                                  <Tooltip label={copied ? 'Copied' : 'Copy request URL'}>
                                    <ActionIcon
                                      aria-label="Request URL"
                                      variant="subtle"
                                      size="xs"
                                      color="gray"
                                      onClick={copy}
                                    >
                                      {copied ? <IconCheck size={12} /> : <IconCopy size={12} />}
                                    </ActionIcon>
                                  </Tooltip>
                                )}
                              </CopyButton>
                            </Group>
                          )}
                          {integration.provider === 'teams' && (
                            <Text fz={11} c="dimmed" truncate maw={260}>
                              {integration.status === 'active'
                                ? `${integration.teamsOrganization ?? '—'} · approved by ${
                                    integration.teamsApprovedBy ?? 'an administrator'
                                  } · files ${integration.teamsFileAccess ? 'on' : 'off'}`
                                : 'Waiting for a Microsoft 365 administrator to approve'}
                            </Text>
                          )}
                          {/* Which Azure project this connection is pinned to, and
                              WHOSE identity it acts as — a PAT connection acts as
                              the token's owner, not as the application. */}
                          {integration.provider === 'azure_devops' && (
                            <Text fz={11} c="dimmed" truncate maw={260}>
                              {integration.azureOrganization ?? '—'}
                              {integration.azureProjectDisplayNames?.length
                                ? ` / ${integration.azureProjectDisplayNames.join(', ')}`
                                : integration.azureProjectName
                                  ? ` / ${integration.azureProjectName}`
                                  : ''}
                              {' · '}
                              {integration.azureAuthMode === 'pat'
                                ? `as ${integration.connectedBy.name} (token)`
                                : `as ${integration.azureIdentity ?? 'the Aixle application'}`}
                            </Text>
                          )}
                          {/* A token connection acts as the person who pasted it,
                              and receives no GitHub webhooks — both are worth
                              seeing on the row rather than only in the dialog. */}
                          {integration.provider === 'github' && integration.githubAuthMode === 'pat' && (
                            <Text fz={11} c="dimmed" truncate maw={260}>
                              {`token · as ${integration.connectedBy.name}`}
                              {integration.githubTokenScopes?.length
                                ? ` · ${integration.githubTokenScopes.join(', ')}`
                                : ''}
                            </Text>
                          )}
                          {integration.githubError && (
                            <Tooltip label={integration.githubError} multiline maw={360}>
                              <Text fz={11} c="red.6" truncate maw={260}>
                                {integration.githubError}
                              </Text>
                            </Tooltip>
                          )}
                          {/* Whose identity it acts as matters most on a 3LO
                              connection, which acts as the person who signed in. */}
                          {integration.provider === 'jira' && (
                            <Text fz={11} c="dimmed" truncate maw={260}>
                              {integration.status === 'inactive'
                                ? 'Choose the Jira projects to finish connecting'
                                : `${integration.jiraProjects.map((p) => p.key).join(', ') || 'no projects'} · as ${
                                    integration.jiraIdentity ?? integration.connectedBy.name
                                  } (${integration.jiraAuthMode === 'oauth' ? 'Atlassian account' : 'service account'})`}
                            </Text>
                          )}
                          {integration.githubProjects.length > 0 && (
                            <Text fz={11} c="dimmed" truncate maw={260}>
                              {`projects: ${integration.githubProjects.map((p) => p.title).join(', ')}`}
                            </Text>
                          )}
                          {integration.provider === 'linear' && (
                            <Text fz={11} c="dimmed" truncate maw={260}>
                              {integration.status === 'inactive'
                                ? 'Choose the Linear teams to finish connecting'
                                : `${integration.linearTeams.map((t) => t.key).join(', ') || 'no teams'} · as ${
                                    integration.linearIdentity ?? integration.connectedBy.name
                                  } (${integration.linearAuthMode === 'oauth' ? 'Linear app' : 'API key'})`}
                            </Text>
                          )}
                          {integration.provider === 'youtrack' && (
                            <Text fz={11} c="dimmed" truncate maw={260}>
                              {`${integration.youtrackProjects.map((p) => p.key).join(', ') || 'no projects'} · as @${
                                integration.youtrackIdentity ?? integration.connectedBy.name
                              } (permanent token)`}
                            </Text>
                          )}
                          {integration.youtrackWebhooksPending.length > 0 && (
                            <Text fz={11} c="yellow.7" truncate maw={260}>
                              {`No webhook event yet from ${integration.youtrackWebhooksPending.join(', ')}`}
                            </Text>
                          )}
                          {integration.linearWebhookError && (
                            <Tooltip label={integration.linearWebhookError} multiline maw={360}>
                              <Text fz={11} c="red.6" truncate maw={260}>
                                {integration.linearWebhookError}
                              </Text>
                            </Tooltip>
                          )}
                          {TOKEN_PROVIDERS.has(integration.provider) &&
                            integration.status === 'error' &&
                            typeof integration.settings.error === 'string' && (
                              <Text fz={11} c="var(--app-danger-fg)" truncate maw={260}>
                                {integration.settings.error}
                              </Text>
                            )}
                          {integration.provider === 'coder' && integration.coderUrl && (
                            <Text fz={11} c="dimmed" truncate maw={200}>
                              {integration.coderUrl}
                            </Text>
                          )}
                          {/* The allocator reads these three, and a missing template is
                              why it can never create a machine — so show them here
                              instead of only inside the connect form. */}
                          {integration.provider === 'coder' && (
                            <Text fz={11} c="dimmed" truncate maw={260}>
                              {integration.coderDefaultTemplate
                                ? `template ${integration.coderDefaultTemplate}`
                                : 'no default template'}
                              {' · '}
                              {integration.coderMachinePrefix
                                ? `prefix ${integration.coderMachinePrefix}`
                                : 'no prefix'}
                              {` · lock ${integration.coderLockTtlMinutes ?? DEFAULT_CODER_LOCK_TTL}m`}
                            </Text>
                          )}
                        </Box>
                      </Group>
                    </Table.Td>
                    <Table.Td>
                      <Text fz={13} c="dimmed">
                        {PROVIDER_LABELS[integration.provider] ?? integration.provider}
                      </Text>
                    </Table.Td>
                    {isProjectContext && (
                      <Table.Td>
                        <Badge color={SCOPE_COLORS[integration.scopeIndicator] ?? 'gray'} size="sm" variant="light">
                          {integration.scopeIndicator}
                        </Badge>
                      </Table.Td>
                    )}
                    <Table.Td>
                      <StatusBadge state={integration.status} size="sm" />
                    </Table.Td>
                    <Table.Td>
                      <Text fz={13} c="dimmed">
                        {integration.connectedBy.name} · {formatDateMedium(integration.createdAt)}
                      </Text>
                    </Table.Td>
                    <Table.Td>
                      <Group gap={4} justify="flex-end">
                        {integration.provider === 'github' && canExecute && !readOnly && (
                          <Tooltip label="Test connection">
                            <ActionIcon
                              aria-label={`Test connection for ${integration.name}`}
                              variant="subtle"
                              size="sm"
                              onClick={() => handleTestConnection(integration)}
                            >
                              <IconRefresh size={16} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                        {integration.githubProjectsSupported && canExecute && !readOnly && (
                          <Tooltip label="GitHub Projects">
                            <ActionIcon
                              aria-label={`GitHub Projects for ${integration.name}`}
                              variant="subtle"
                              size="sm"
                              onClick={() => setGithubProjectsTarget(integration)}
                            >
                              <IconLayoutKanban size={16} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                        {integration.githubUrl && !readOnly && (
                          <Tooltip label="Settings">
                            <ActionIcon
                              aria-label="Settings"
                              variant="subtle"
                              size="sm"
                              component="a"
                              href={integration.githubUrl}
                              target="_blank"
                            >
                              <IconSettings size={16} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                        {integration.provider === 'teams' && canExecute && integration.status === 'active' && (
                          <Tooltip label="Download the Teams app">
                            <ActionIcon
                              aria-label={`Download the Teams app for ${integration.name}`}
                              variant="subtle"
                              size="sm"
                              component="a"
                              href={`${basePath}/${integration.id}/teams_package`}
                            >
                              <IconDownload size={16} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                        {integration.provider === 'teams' && canExecute && integration.status !== 'active' && (
                          <Tooltip label="New approval link">
                            <ActionIcon
                              aria-label={`New approval link for ${integration.name}`}
                              variant="subtle"
                              size="sm"
                              onClick={handleConnectTeams}
                            >
                              <IconLink size={16} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                        {integration.provider === 'azure_devops' && canExecute && !readOnly && (
                          <Tooltip label="Test connection">
                            <ActionIcon
                              aria-label={`Test connection for ${integration.name}`}
                              variant="subtle"
                              size="sm"
                              onClick={() => handleTestConnection(integration)}
                            >
                              <IconRefresh size={16} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                        {integration.provider === 'azure_devops' && integration.azureUrl && !readOnly && (
                          <Tooltip label="Open in Azure DevOps">
                            <ActionIcon
                              aria-label={`Open ${integration.name} in Azure DevOps`}
                              variant="subtle"
                              size="sm"
                              component="a"
                              href={integration.azureUrl}
                              target="_blank"
                            >
                              <IconSettings size={16} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                        {integration.provider === 'jira' && canExecute && !readOnly && (
                          <>
                            {integration.status !== 'inactive' && (
                              <Tooltip label="Test connection">
                                <ActionIcon
                                  aria-label={`Test connection for ${integration.name}`}
                                  variant="subtle"
                                  size="sm"
                                  onClick={() => handleTestConnection(integration)}
                                >
                                  <IconRefresh size={16} />
                                </ActionIcon>
                              </Tooltip>
                            )}
                            <Tooltip label="Jira projects">
                              <ActionIcon
                                aria-label={`Jira projects for ${integration.name}`}
                                variant="subtle"
                                size="sm"
                                onClick={() => setJiraProjectsTarget(integration)}
                              >
                                <IconPencil size={16} />
                              </ActionIcon>
                            </Tooltip>
                            {integration.jiraAuthMode === 'service_account' && (
                              <Tooltip label="Webhook setup">
                                <ActionIcon
                                  aria-label={`Webhook setup for ${integration.name}`}
                                  variant="subtle"
                                  size="sm"
                                  onClick={() => setJiraWebhookTarget(integration)}
                                >
                                  <IconWebhook size={16} />
                                </ActionIcon>
                              </Tooltip>
                            )}
                          </>
                        )}
                        {integration.provider === 'jira' && integration.jiraSiteUrl && !readOnly && (
                          <Tooltip label="Open in Jira">
                            <ActionIcon
                              aria-label={`Open ${integration.name} in Jira`}
                              variant="subtle"
                              size="sm"
                              component="a"
                              href={integration.jiraSiteUrl}
                              target="_blank"
                            >
                              <IconSettings size={16} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                        {integration.provider === 'linear' && canExecute && !readOnly && (
                          <>
                            {integration.status !== 'inactive' && (
                              <Tooltip label="Test connection">
                                <ActionIcon
                                  aria-label={`Test connection for ${integration.name}`}
                                  variant="subtle"
                                  size="sm"
                                  onClick={() => handleTestConnection(integration)}
                                >
                                  <IconRefresh size={16} />
                                </ActionIcon>
                              </Tooltip>
                            )}
                            <Tooltip label="Linear teams">
                              <ActionIcon
                                aria-label={`Linear teams for ${integration.name}`}
                                variant="subtle"
                                size="sm"
                                onClick={() => setLinearTeamsTarget(integration)}
                              >
                                <IconPencil size={16} />
                              </ActionIcon>
                            </Tooltip>
                          </>
                        )}
                        {integration.provider === 'linear' && integration.linearWorkspaceUrl && !readOnly && (
                          <Tooltip label="Open in Linear">
                            <ActionIcon
                              aria-label={`Open ${integration.name} in Linear`}
                              variant="subtle"
                              size="sm"
                              component="a"
                              href={integration.linearWorkspaceUrl}
                              target="_blank"
                            >
                              <IconSettings size={16} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                        {integration.provider === 'youtrack' && canExecute && !readOnly && (
                          <>
                            {integration.status !== 'inactive' && (
                              <Tooltip label="Test connection">
                                <ActionIcon
                                  aria-label={`Test connection for ${integration.name}`}
                                  variant="subtle"
                                  size="sm"
                                  onClick={() => handleTestConnection(integration)}
                                >
                                  <IconRefresh size={16} />
                                </ActionIcon>
                              </Tooltip>
                            )}
                            <Tooltip label="YouTrack projects">
                              <ActionIcon
                                aria-label={`YouTrack projects for ${integration.name}`}
                                variant="subtle"
                                size="sm"
                                onClick={() => setYoutrackProjectsTarget(integration)}
                              >
                                <IconPencil size={16} />
                              </ActionIcon>
                            </Tooltip>
                            <Tooltip label="Webhook setup">
                              <ActionIcon
                                aria-label={`Webhook setup for ${integration.name}`}
                                variant="subtle"
                                size="sm"
                                onClick={() => setYoutrackWebhookTarget(integration)}
                              >
                                <IconWebhook size={16} />
                              </ActionIcon>
                            </Tooltip>
                          </>
                        )}
                        {integration.provider === 'youtrack' && integration.youtrackBaseUrl && !readOnly && (
                          <Tooltip label="Open in YouTrack">
                            <ActionIcon
                              aria-label={`Open ${integration.name} in YouTrack`}
                              variant="subtle"
                              size="sm"
                              component="a"
                              href={integration.youtrackBaseUrl}
                              target="_blank"
                            >
                              <IconSettings size={16} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                        {TOKEN_PROVIDERS.has(integration.provider) && canExecute && !readOnly && (
                          <>
                            <Tooltip label="Test connection">
                              <ActionIcon
                                aria-label={`Test connection for ${integration.name}`}
                                variant="subtle"
                                size="sm"
                                onClick={() => handleTestConnection(integration)}
                              >
                                <IconRefresh size={16} />
                              </ActionIcon>
                            </Tooltip>
                            <Tooltip label="Replace token">
                              <ActionIcon
                                aria-label={`Replace token for ${integration.name}`}
                                variant="subtle"
                                size="sm"
                                onClick={() => setTokenTarget(integration)}
                              >
                                <IconKey size={16} />
                              </ActionIcon>
                            </Tooltip>
                          </>
                        )}
                        {integration.provider === 'coder' && canExecute && !readOnly && (
                          <Tooltip label="Edit settings">
                            <ActionIcon
                              aria-label={`Edit settings for ${integration.name}`}
                              variant="subtle"
                              size="sm"
                              onClick={() => openCoderSettings(integration)}
                            >
                              <IconPencil size={16} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                        {canExecute && (!readOnly || canManageCompany) && (
                          <Tooltip label="Remove">
                            <ActionIcon
                              aria-label="Remove"
                              variant="subtle"
                              size="sm"
                              color="red"
                              onClick={() => handleDelete(integration)}
                            >
                              <IconTrash size={16} />
                            </ActionIcon>
                          </Tooltip>
                        )}
                      </Group>
                    </Table.Td>
                  </Table.Tr>
                );
              })}
            </Table.Tbody>
          </Table>
        </ResourceTableShell>
      )}

      {jira && (
        <>
          <JiraConnectModal opened={jiraOpen} onClose={() => setJiraOpen(false)} basePath={basePath} jira={jira} />
          <JiraProjectsModal
            integration={jiraProjectsTarget}
            onClose={() => setJiraProjectsTarget(null)}
            basePath={basePath}
          />
          <JiraWebhookModal
            integration={jiraWebhookTarget}
            onClose={() => setJiraWebhookTarget(null)}
            basePath={basePath}
          />
        </>
      )}

      {linear && (
        <>
          <LinearConnectModal
            opened={linearOpen}
            onClose={() => setLinearOpen(false)}
            basePath={basePath}
            linear={linear}
          />
          <LinearTeamsModal
            integration={linearTeamsTarget}
            onClose={() => setLinearTeamsTarget(null)}
            basePath={basePath}
          />
        </>
      )}

      {youtrack && (
        <>
          <YoutrackConnectModal opened={youtrackOpen} onClose={() => setYoutrackOpen(false)} basePath={basePath} />
          <YoutrackProjectsModal
            integration={youtrackProjectsTarget}
            onClose={() => setYoutrackProjectsTarget(null)}
            basePath={basePath}
          />
          <YoutrackWebhookModal
            integration={youtrackWebhookTarget}
            onClose={() => setYoutrackWebhookTarget(null)}
            basePath={basePath}
          />
        </>
      )}

      <GithubProjectsModal
        integration={githubProjectsTarget}
        onClose={() => setGithubProjectsTarget(null)}
        basePath={basePath}
      />

      {azureDevops && (
        <AzureDevopsConnectModal
          opened={azureOpen}
          onClose={() => {
            setAzureOpen(false);
            setAzureSignIn(null);
          }}
          signIn={azureSignIn}
          basePath={basePath}
          azureDevops={azureDevops}
        />
      )}

      <GithubConnectModal
        opened={githubOpen}
        onClose={() => setGithubOpen(false)}
        basePath={basePath}
        github={github}
      />

      <Modal opened={gitlabOpen} onClose={requestCloseGitlab} title="Connect GitLab" centered size="sm">
        <Stack gap="md">
          <Text size="sm" c="dimmed">
            Enter a GitLab Personal Access Token with <b>api</b> scope to connect your GitLab account.
          </Text>
          <PasswordInput
            label="Personal Access Token"
            placeholder="glpat-..."
            value={gitlabPat}
            onChange={(e) => setGitlabPat(e.currentTarget.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') handleConnectGitlab();
            }}
            autoFocus
          />
          {gitlabError && (
            <Text size="sm" c="var(--app-danger-fg)">
              {gitlabError}
            </Text>
          )}
          <Group justify="flex-end">
            <Button variant="default" onClick={requestCloseGitlab}>
              Cancel
            </Button>
            <Button onClick={handleConnectGitlab} loading={gitlabLoading} disabled={!gitlabPat.trim()}>
              Connect
            </Button>
          </Group>
        </Stack>
      </Modal>

      <Modal opened={coderOpen} onClose={requestCloseCoder} title="Connect Coder" centered size="sm">
        <Stack gap="md">
          <Text size="sm" c="dimmed">
            Enter your Coder instance URL and a session token with full workspace permissions.
          </Text>
          <TextInput
            label="Coder URL"
            placeholder="https://coder.example.com"
            value={coderUrl}
            onChange={(e) => setCoderUrl(e.currentTarget.value)}
            error={coderUrl.trim() && !isValidHttpUrl(coderUrl) ? 'Must be a valid http or https URL' : undefined}
            autoFocus
          />
          <PasswordInput
            label="Session Token"
            placeholder="vFVrbTLdls-..."
            value={coderToken}
            onChange={(e) => setCoderToken(e.currentTarget.value)}
          />

          <UnstyledButton onClick={() => setCoderAdvancedOpen((open) => !open)}>
            <Group gap={4}>
              {coderAdvancedOpen ? <IconChevronDown size={14} /> : <IconChevronRight size={14} />}
              <Text size="sm" c="dimmed">
                Advanced
              </Text>
            </Group>
          </UnstyledButton>

          {coderAdvancedOpen && (
            <Stack gap="sm">
              <TextInput
                label="Default template"
                placeholder="aws-ec2-spot-v1"
                value={coderDefaultTemplate}
                onChange={(e) => setCoderDefaultTemplate(e.currentTarget.value)}
              />
              <TextInput
                label="Machine name prefix"
                placeholder="aixle-prod"
                value={coderMachinePrefix}
                onChange={(e) => setCoderMachinePrefix(e.currentTarget.value)}
              />
              <NumberInput
                label="Lock TTL (minutes)"
                min={1}
                max={1440}
                value={coderLockTtlMinutes}
                onChange={(value) => setCoderLockTtlMinutes(value)}
                error={typeof coderLockTtlMinutes === 'number' && coderLockTtlMinutes > 0 ? undefined : 'Required'}
              />
            </Stack>
          )}

          {coderError && (
            <Text size="sm" c="var(--app-danger-fg)">
              {coderError}
            </Text>
          )}

          <Group justify="flex-end">
            <Button variant="default" onClick={requestCloseCoder}>
              Cancel
            </Button>
            <Button
              onClick={handleConnectCoder}
              loading={coderLoading}
              disabled={
                !coderUrl.trim() ||
                !coderToken.trim() ||
                !isValidHttpUrl(coderUrl) ||
                !(typeof coderLockTtlMinutes === 'number' && coderLockTtlMinutes > 0)
              }
            >
              Connect
            </Button>
          </Group>
        </Stack>
      </Modal>

      <Modal opened={!!tokenTarget} onClose={requestCloseToken} title="Replace token" centered size="sm">
        <Stack gap="md">
          <Text size="sm" c="dimmed">
            {tokenTarget?.provider === 'coder'
              ? 'Paste a new Coder session token. It is checked against Coder before it replaces the current one.'
              : 'Paste a new GitLab personal access token with the api scope. It is checked against GitLab before it replaces the current one.'}{' '}
            Repositories and settings stay as they are.
          </Text>
          <PasswordInput
            label={tokenTarget?.provider === 'coder' ? 'Session Token' : 'Personal Access Token'}
            value={replacementToken}
            onChange={(e) => setReplacementToken(e.currentTarget.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') handleReplaceToken();
            }}
            autoFocus
          />
          {tokenError && (
            <Text size="sm" c="var(--app-danger-fg)">
              {tokenError}
            </Text>
          )}
          <Group justify="flex-end">
            <Button variant="default" onClick={requestCloseToken}>
              Cancel
            </Button>
            <Button onClick={handleReplaceToken} loading={tokenLoading} disabled={!replacementToken.trim()}>
              Replace
            </Button>
          </Group>
        </Stack>
      </Modal>

      <Modal opened={!!coderEditTarget} onClose={requestCloseCoderSettings} title="Coder settings" centered size="sm">
        <Stack gap="md">
          <Text size="sm" c="dimmed">
            Without a default template the allocator can only hand out workspaces that already exist — it never creates
            one. Leave it blank to cap the pool at its current size.
          </Text>
          <TextInput
            label="Default template"
            placeholder="aws-ec2-spot-v1"
            value={coderEditTemplate}
            onChange={(e) => setCoderEditTemplate(e.currentTarget.value)}
            autoFocus
          />
          <TextInput
            label="Machine name prefix"
            placeholder="aixle-prod"
            value={coderEditPrefix}
            onChange={(e) => setCoderEditPrefix(e.currentTarget.value)}
          />
          <NumberInput
            label="Lock TTL (minutes)"
            min={1}
            max={1440}
            value={coderEditTtl}
            onChange={(value) => setCoderEditTtl(value)}
            error={typeof coderEditTtl === 'number' && coderEditTtl > 0 ? undefined : 'Required'}
          />
          <Group justify="flex-end">
            <Button variant="default" onClick={requestCloseCoderSettings}>
              Cancel
            </Button>
            <Button
              onClick={handleSaveCoderSettings}
              loading={coderEditLoading}
              disabled={!(typeof coderEditTtl === 'number' && coderEditTtl > 0)}
            >
              Save
            </Button>
          </Group>
        </Stack>
      </Modal>

      <TeamsApprovalModal
        url={teamsApprovalUrl !== dismissedApprovalUrl ? teamsApprovalUrl : null}
        onClose={() => setDismissedApprovalUrl(teamsApprovalUrl)}
      />
    </Box>
  );
};
