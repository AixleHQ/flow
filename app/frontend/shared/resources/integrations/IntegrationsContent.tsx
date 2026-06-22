import { router, usePage } from '@inertiajs/react';
import {
  Badge,
  Box,
  Button,
  Card,
  Divider,
  Group,
  Menu,
  Modal,
  NumberInput,
  PasswordInput,
  Stack,
  Text,
  TextInput,
  ThemeIcon,
  Title,
  UnstyledButton,
} from '@mantine/core';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import {
  IconBrandGithub,
  IconChevronDown,
  IconChevronRight,
  IconLink,
  IconPlus,
  IconSettings,
  IconTrash,
} from '@tabler/icons-react';
import { useCallback, useMemo, useState } from 'react';

import { isValidHttpsUrl } from 'shared/lib/urlValidation';

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
  connectedBy: { id: number; name: string };
  createdAt: string;
}

interface IntegrationsContentProps {
  integrations: Integration[];
  basePath: string;
  title: string;
}

const STATUS_COLORS: Record<string, string> = {
  active: 'green',
  inactive: 'yellow',
  error: 'red',
};

const GitlabIcon = () => <img src="/images/gitlab.svg" alt="GitLab" width={20} height={20} />;
const CoderIcon = ({ size = 20 }: { size?: number } = {}) => (
  <img src="/images/coder.svg" alt="Coder" width={size} height={size} />
);

const ProviderIcon = ({ provider, size = 20 }: { provider: string; size?: number }) => {
  if (provider === 'github') return <IconBrandGithub size={size} />;
  if (provider === 'gitlab') return <img src="/images/gitlab.svg" alt="GitLab" width={size} height={size} />;
  if (provider === 'coder') return <img src="/images/coder.svg" alt="Coder" width={size} height={size} />;
  return <IconLink size={size} />;
};

const PROVIDER_ICON_COLORS: Record<string, string> = {
  github: 'dark',
  gitlab: 'orange',
  coder: 'blue',
};

const formatDate = (d: string) =>
  new Date(d).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });

function getGithubInstallUrl(basePath: string, githubAppSlug: string | null): string {
  if (!githubAppSlug) return '/company/integrations/github_setup';

  const base = `https://github.com/apps/${githubAppSlug}/installations/new`;
  const projectMatch = basePath.match(/projects\/(\d+)/);
  if (projectMatch) return `${base}?state=${encodeURIComponent(`project:${projectMatch[1]}`)}`;
  return base;
}

const IntegrationCard = ({
  integration,
  readOnly,
  onDelete,
  onLink,
}: {
  integration: Integration;
  readOnly?: boolean;
  onDelete: (i: Integration) => void;
  onLink?: (i: Integration) => void;
}) => (
  <Card withBorder p="md" radius="md">
    <Group justify="space-between" wrap="nowrap">
      <Group gap="md" wrap="nowrap">
        <ThemeIcon variant="light" size="lg" radius="md" color={PROVIDER_ICON_COLORS[integration.provider] ?? 'gray'}>
          <ProviderIcon provider={integration.provider} size={18} />
        </ThemeIcon>
        <Box>
          <Group gap="xs">
            <Text fw={600} size="sm">
              {integration.name}
            </Text>
            <Badge color={STATUS_COLORS[integration.status] ?? 'gray'} size="sm" variant="light">
              {integration.status}
            </Badge>
            {readOnly && (
              <Badge size="xs" variant="outline" color="gray">
                company
              </Badge>
            )}
          </Group>
          <Text size="xs" c="dimmed">
            Connected by {integration.connectedBy.name} on {formatDate(integration.createdAt)}
          </Text>
        </Box>
      </Group>

      <Group gap="xs">
        {onLink && integration.status === 'active' && (
          <Button variant="light" size="xs" leftSection={<IconLink size={14} />} onClick={() => onLink(integration)}>
            Link to project
          </Button>
        )}
        {integration.githubUrl && !readOnly && (
          <Button
            variant="subtle"
            size="xs"
            leftSection={<IconSettings size={14} />}
            component="a"
            href={integration.githubUrl}
            target="_blank"
          >
            Settings
          </Button>
        )}
        {!readOnly && (
          <Button
            variant="subtle"
            color="red"
            size="xs"
            leftSection={<IconTrash size={14} />}
            onClick={() => onDelete(integration)}
          >
            Remove
          </Button>
        )}
      </Group>
    </Group>
  </Card>
);

export const IntegrationsContent = ({ integrations, basePath, title }: IntegrationsContentProps) => {
  const { settings } = usePage<{ settings: { githubAppSlug: string | null } }>().props;
  const isProjectContext = basePath.includes('projects');
  const [gitlabOpen, setGitlabOpen] = useState(false);
  const [gitlabPat, setGitlabPat] = useState('');
  const [gitlabLoading, setGitlabLoading] = useState(false);

  const [coderOpen, setCoderOpen] = useState(false);
  const [coderUrl, setCoderUrl] = useState('');
  const [coderToken, setCoderToken] = useState('');
  const [coderDefaultTemplate, setCoderDefaultTemplate] = useState('');
  const [coderMachinePrefix, setCoderMachinePrefix] = useState('');
  const [coderLockTtlMinutes, setCoderLockTtlMinutes] = useState<number | string>(60);
  const [coderAdvancedOpen, setCoderAdvancedOpen] = useState(false);
  const [coderLoading, setCoderLoading] = useState(false);
  const [coderError, setCoderError] = useState<string | null>(null);

  const resetCoderForm = useCallback(() => {
    setCoderUrl('');
    setCoderToken('');
    setCoderDefaultTemplate('');
    setCoderMachinePrefix('');
    setCoderLockTtlMinutes(60);
    setCoderAdvancedOpen(false);
    setCoderError(null);
  }, []);

  const closeCoderModal = useCallback(() => {
    setCoderOpen(false);
    resetCoderForm();
  }, [resetCoderForm]);

  const projectIntegrations = useMemo(() => integrations.filter((i) => i.scopeIndicator === 'project'), [integrations]);
  const companyIntegrations = useMemo(() => integrations.filter((i) => i.scopeIndicator === 'company'), [integrations]);

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
    const url = getGithubInstallUrl(basePath, settings.githubAppSlug);
    window.location.href = url;
  }, [basePath, settings.githubAppSlug]);

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
    if (!isValidHttpsUrl(trimmedUrl)) {
      setCoderError('Coder URL must be a valid https URL');
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

  const alreadyLinkedInstallationIds = useMemo(
    () => new Set(projectIntegrations.filter((i) => i.installationId).map((i) => i.installationId)),
    [projectIntegrations],
  );

  const renderSection = (
    label: string,
    items: Integration[],
    options: { readOnly?: boolean; showLink?: boolean } = {},
  ) => (
    <Box>
      <Group gap="xs" mb="sm">
        <Text fw={600} size="sm" tt="uppercase" c="dimmed" lts={0.5}>
          {label}
        </Text>
        <Badge size="xs" variant="light" color="gray">
          {items.length}
        </Badge>
      </Group>
      {items.length === 0 ? (
        <Text c="dimmed" size="sm" mb="md">
          {options.readOnly ? 'No company-wide integrations available.' : 'No integrations in this scope.'}
        </Text>
      ) : (
        <Stack gap="sm" mb="md">
          {items.map((integration) => (
            <IntegrationCard
              key={integration.id}
              integration={integration}
              readOnly={options.readOnly}
              onDelete={handleDelete}
              onLink={
                options.showLink && !alreadyLinkedInstallationIds.has(integration.installationId)
                  ? handleLinkToProject
                  : undefined
              }
            />
          ))}
        </Stack>
      )}
    </Box>
  );

  return (
    <Box>
      <Group justify="space-between" mb="lg">
        <Box>
          <Title order={2}>{title}</Title>
          <Text size="sm" c="dimmed" mt={2}>
            {isProjectContext
              ? 'Connect GitHub or GitLab for this project, or use company-wide integrations'
              : 'Connect external services to your company'}
          </Text>
        </Box>
        <Menu position="bottom-end" withArrow>
          <Menu.Target>
            <Button leftSection={<IconPlus size={16} />}>Connect</Button>
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
          </Menu.Dropdown>
        </Menu>
      </Group>

      {integrations.length === 0 ? (
        <Card p="xl" withBorder radius="md">
          <Stack align="center" gap="md" py="lg">
            <ThemeIcon size={56} radius="xl" variant="light" color="gray">
              <IconLink size={28} />
            </ThemeIcon>
            <Box ta="center">
              <Text fw={500} size="lg">
                No integrations connected
              </Text>
              <Text size="sm" c="dimmed" mt={4} maw={400}>
                {isProjectContext
                  ? 'Add a project-scoped GitHub or GitLab installation, or rely on company integrations'
                  : 'Connect GitHub or GitLab to access repositories in agent sessions'}
              </Text>
            </Box>
            <Group gap="sm">
              <Button variant="outline" leftSection={<IconBrandGithub size={16} />} onClick={handleConnectGithub}>
                Connect GitHub
              </Button>
              <Button variant="outline" leftSection={<GitlabIcon />} onClick={() => setGitlabOpen(true)}>
                Connect GitLab
              </Button>
            </Group>
          </Stack>
        </Card>
      ) : isProjectContext ? (
        <Stack gap="lg">
          {renderSection('This Project', projectIntegrations)}
          <Divider />
          {renderSection('Company-wide', companyIntegrations, { readOnly: true, showLink: true })}
        </Stack>
      ) : (
        <Stack gap="sm">
          {integrations.map((integration) => (
            <IntegrationCard key={integration.id} integration={integration} onDelete={handleDelete} />
          ))}
        </Stack>
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
            error={coderUrl.trim() && !isValidHttpsUrl(coderUrl) ? 'Must be a valid https URL' : undefined}
            autoFocus
            required
          />
          <PasswordInput
            label="Session Token"
            placeholder="vFVrbTLdls-..."
            value={coderToken}
            onChange={(e) => setCoderToken(e.currentTarget.value)}
            required
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
                required
                error={typeof coderLockTtlMinutes === 'number' && coderLockTtlMinutes > 0 ? undefined : 'Required'}
              />
            </Stack>
          )}

          {coderError && (
            <Text size="sm" c="red">
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
                !isValidHttpsUrl(coderUrl) ||
                !(typeof coderLockTtlMinutes === 'number' && coderLockTtlMinutes > 0)
              }
            >
              Connect
            </Button>
          </Group>
        </Stack>
      </Modal>
    </Box>
  );
};
