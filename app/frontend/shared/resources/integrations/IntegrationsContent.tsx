import { router } from '@inertiajs/react';
import {
  ActionIcon,
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
  IconBrandGithub,
  IconBrandSlack,
  IconCheck,
  IconChevronDown,
  IconChevronRight,
  IconCopy,
  IconLink,
  IconPencil,
  IconPlus,
  IconSearch,
  IconSettings,
  IconTrash,
} from '@tabler/icons-react';
import { useCallback, useMemo, useState } from 'react';

import { formatDateMedium } from 'shared/lib/formatDate';
import { useProjectPermissions } from 'shared/lib/hooks/useProjectPermissions';
import { isValidHttpUrl } from 'shared/lib/urlValidation';
import { EmptyState } from 'shared/ui/EmptyState';
import { PageHeader } from 'shared/ui/PageHeader';
import { ResourceCount, ResourceTableShell, ResourceTh } from 'shared/ui/ResourceTable';
import { StatusBadge } from 'shared/ui/StatusBadge';

export interface Integration {
  id: number;
  name: string;
  provider: string;
  status: string;
  scopeIndicator: string;
  githubUrl: string | null;
  installationId?: string;
  coderUrl?: string | null;
  coderDefaultTemplate?: string | null;
  coderMachinePrefix?: string | null;
  coderLockTtlMinutes?: number | null;
  slackRequestUrl?: string | null;
  connectedBy: { id: number; name: string };
  createdAt: string;
}

interface IntegrationsContentProps {
  integrations: Integration[];
  basePath: string;
  title: string;
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
  return <IconLink size={size} />;
};

const PROVIDER_LABELS: Record<string, string> = {
  github: 'GitHub',
  gitlab: 'GitLab',
  coder: 'Coder',
  slack: 'Slack',
};

const SCOPE_COLORS: Record<string, string> = {
  company: 'gray',
  project: 'green',
};

// Mirrors the server-side fallback in Coder::LockService#ttl_minutes.
const DEFAULT_CODER_LOCK_TTL = 120;

export const IntegrationsContent = ({ integrations, basePath, title }: IntegrationsContentProps) => {
  const { canExecute } = useProjectPermissions();
  const isProjectContext = basePath.includes('projects');
  const [search, setSearch] = useState('');
  const [scopeFilter, setScopeFilter] = useState('all');
  const [connectMenuOpened, setConnectMenuOpened] = useState(false);

  const [gitlabOpen, setGitlabOpen] = useState(false);
  const [gitlabPat, setGitlabPat] = useState('');
  const [gitlabLoading, setGitlabLoading] = useState(false);

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

  const alreadyLinkedInstallationIds = useMemo(
    () =>
      new Set(
        integrations.filter((i) => i.scopeIndicator === 'project' && i.installationId).map((i) => i.installationId),
      ),
    [integrations],
  );

  const handleDelete = useCallback(
    (integration: Integration) => {
      modals.openConfirmModal({
        title: 'Remove Integration',
        children: (
          <Text size="sm">
            Are you sure you want to remove <b>{integration.name}</b>? This will also disconnect all repositories linked
            through this integration.
          </Text>
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

  const handleConnectGithub = useCallback(() => {
    // Server-side endpoint mints a SIGNED state (Oauth::State) and redirects to GitHub's
    // app-install URL — the state is never built or forgeable client-side (§7).
    window.location.href = `${basePath}/github_app_install`;
  }, [basePath]);

  const handleLinkToProject = useCallback(
    (integration: Integration) => {
      if (!integration.installationId) return;
      router.post(
        basePath,
        { provider: 'github', installationId: integration.installationId },
        {
          preserveScroll: true,
          onSuccess: () => notifications.show({ message: `${integration.name} linked to project`, color: 'green' }),
          onError: () => notifications.show({ message: 'Failed to link integration', color: 'red' }),
        },
      );
    },
    [basePath],
  );

  const handleConnectGitlab = useCallback(() => {
    if (!gitlabPat.trim()) return;
    setGitlabLoading(true);

    router.post(
      basePath,
      {
        provider: 'gitlab',
        personalAccessToken: gitlabPat.trim(),
      },
      {
        preserveScroll: true,
        onSuccess: () => {
          setGitlabOpen(false);
          setGitlabPat('');
        },
        onError: () => {
          notifications.show({ message: 'Failed to connect GitLab', color: 'red' });
        },
        onFinish: () => setGitlabLoading(false),
      },
    );
  }, [basePath, gitlabPat]);

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
      onError: (errors) => {
        const message =
          typeof errors === 'object' && errors ? Object.values(errors).join(' ') : 'Failed to connect Coder';
        setCoderError(message || 'Failed to connect Coder');
        notifications.show({ message: 'Failed to connect Coder', color: 'red' });
      },
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

  // Slack connects via OAuth: redirect to the project-scoped start action, which
  // bounces to Slack's consent screen. The install binds to this project.
  const handleConnectSlack = useCallback(() => {
    window.location.href = `${basePath}/slack_oauth_start`;
  }, [basePath]);

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
                {isProjectContext && (
                  <Menu.Item leftSection={<IconBrandSlack size={16} />} onClick={handleConnectSlack}>
                    Slack
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
                    {isProjectContext && (
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
                const canLink =
                  isProjectContext &&
                  readOnly &&
                  integration.status === 'active' &&
                  integration.installationId &&
                  !alreadyLinkedInstallationIds.has(integration.installationId);

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
                        {canExecute && canLink && (
                          <Tooltip label="Link to project">
                            <ActionIcon
                              aria-label="Link to project"
                              variant="subtle"
                              size="sm"
                              onClick={() => handleLinkToProject(integration)}
                            >
                              <IconLink size={16} />
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
                        {canExecute && !readOnly && (
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

      <Modal
        opened={gitlabOpen}
        onClose={() => {
          setGitlabOpen(false);
          setGitlabPat('');
        }}
        title="Connect GitLab"
        centered
        size="sm"
      >
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
          <Group justify="flex-end">
            <Button
              variant="default"
              onClick={() => {
                setGitlabOpen(false);
                setGitlabPat('');
              }}
            >
              Cancel
            </Button>
            <Button onClick={handleConnectGitlab} loading={gitlabLoading} disabled={!gitlabPat.trim()}>
              Connect
            </Button>
          </Group>
        </Stack>
      </Modal>

      <Modal opened={coderOpen} onClose={closeCoderModal} title="Connect Coder" centered size="sm">
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
            <Button variant="default" onClick={closeCoderModal}>
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

      <Modal
        opened={!!coderEditTarget}
        onClose={() => setCoderEditTarget(null)}
        title="Coder settings"
        centered
        size="sm"
      >
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
            <Button variant="default" onClick={() => setCoderEditTarget(null)}>
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
    </Box>
  );
};
