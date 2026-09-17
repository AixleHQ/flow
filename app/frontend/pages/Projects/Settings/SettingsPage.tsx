import type { FormDataConvertible } from '@inertiajs/core';
import { Head, router, usePage } from '@inertiajs/react';
import {
  Alert,
  Box,
  Button,
  Card,
  Code,
  CopyButton,
  Divider,
  Group,
  Modal,
  Select,
  Stack,
  Switch,
  Text,
  TextInput,
  Textarea,
  Tooltip,
} from '@mantine/core';
import { useForm } from '@mantine/form';
import { modals } from '@mantine/modals';
import { notifications } from '@mantine/notifications';
import {
  IconAdjustments,
  IconAlertTriangle,
  IconArchive,
  IconChartBar,
  IconCheck,
  IconCopy,
  IconInfoCircle,
  IconLock,
  IconTrash,
} from '@tabler/icons-react';
import { zod4Resolver as zodResolver } from 'mantine-form-zod-resolver';
import { useState } from 'react';
import { z } from 'zod';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

import classes from './SettingsPage.module.css';

const LANGUAGE_OPTIONS = [
  { value: 'en', label: 'English' },
  { value: 'ru', label: 'Russian' },
  { value: 'es', label: 'Spanish' },
  { value: 'de', label: 'German' },
  { value: 'fr', label: 'French' },
  { value: 'ja', label: 'Japanese' },
  { value: 'zh', label: 'Chinese' },
  { value: 'pt', label: 'Portuguese' },
  { value: 'it', label: 'Italian' },
  { value: 'pl', label: 'Polish' },
  { value: 'uk', label: 'Ukrainian' },
];

const STATUS_CONFIG: Record<string, { label: string; chipClass: string; dotClass: string }> = {
  active: { label: 'Active', chipClass: 'statusChipOk', dotClass: 'statusDotOk' },
  paused: { label: 'Paused', chipClass: 'statusChipPaused', dotClass: 'statusDotPaused' },
  archived: { label: 'Archived', chipClass: 'statusChipDefault', dotClass: 'statusDotDefault' },
};

const schema = z.object({
  name: z.string().min(1, 'Name is required').max(100),
  description: z.string().max(500).optional(),
  preferredArtifactsLanguage: z.string(),
});

interface Project {
  id: number;
  name: string;
  description: string | null;
  slug: string;
  state: string;
  preferredArtifactsLanguage: string;
  createdAt: string;
  updatedAt: string;
  ownerName: string;
  ownerEmail: string;
  canDelete: boolean;
  shareUsageWithInsights: boolean;
  insightsConnectionConfigured: boolean;
  insightsConnectionTokenLastUsedAt: string | null;
  canManageInsightsSharing: boolean;
  insightsConnectionToken: string | null;
}

interface Props {
  project: Project;
}

function avatarInitials(name: string): string {
  return name
    .split(' ')
    .map((w) => w[0])
    .join('')
    .slice(0, 2)
    .toUpperCase();
}

const SettingsPage = () => {
  const { project } = usePage<{ props: Props }>().props as unknown as Props;
  const basePath = `/company/projects/${project.id}`;

  const form = useForm({
    initialValues: {
      name: project.name,
      description: project.description || '',
      preferredArtifactsLanguage: project.preferredArtifactsLanguage || 'en',
    },
    validate: zodResolver(schema),
  });

  const [saved, setSaved] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [insightsSaving, setInsightsSaving] = useState(false);
  const [tokenGenerating, setTokenGenerating] = useState(false);

  const handleSubmit = (values: typeof form.values) => {
    setIsSubmitting(true);
    router.patch(
      `${basePath}/settings`,
      {
        project: {
          name: values.name.trim(),
          description: values.description.trim(),
          preferredArtifactsLanguage: values.preferredArtifactsLanguage,
        },
      } as Record<string, FormDataConvertible>,
      {
        preserveScroll: true,
        onSuccess: () => {
          setIsSubmitting(false);
          form.resetDirty();
          setSaved(true);
          notifications.show({ message: 'Project settings saved', color: 'green' });
        },
        onError: () => {
          setIsSubmitting(false);
          notifications.show({ message: 'Failed to save settings', color: 'red' });
        },
      },
    );
  };

  const handleInsightsSharingChange = (checked: boolean) => {
    if (!project.canManageInsightsSharing) return;

    setInsightsSaving(true);
    router.patch(
      `${basePath}/settings`,
      {
        project: { shareUsageWithInsights: checked },
      } as Record<string, FormDataConvertible>,
      {
        preserveScroll: true,
        onSuccess: () => {
          setInsightsSaving(false);
          notifications.show({
            message: checked ? 'Insights sharing enabled' : 'Insights sharing disabled',
            color: 'green',
          });
        },
        onError: () => {
          setInsightsSaving(false);
          notifications.show({ message: 'Failed to update Insights sharing', color: 'red' });
        },
      },
    );
  };

  const handleGenerateToken = () => {
    if (!project.canManageInsightsSharing || !project.shareUsageWithInsights) return;

    setTokenGenerating(true);
    router.post(
      `${basePath}/settings/regenerate_insights_connection_token`,
      {},
      {
        preserveScroll: true,
        onFinish: () => setTokenGenerating(false),
        onError: () => {
          notifications.show({ message: 'Failed to generate connection token', color: 'red' });
        },
      },
    );
  };

  const handleArchive = () => {
    modals.openConfirmModal({
      title: 'Archive Project',
      children: (
        <Text size="sm">
          Are you sure you want to archive <b>{project.name}</b>? The project will be hidden from the sidebar but its
          data will be preserved. You can restore it later.
        </Text>
      ),
      labels: { confirm: 'Archive', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => {
        router.patch(
          `${basePath}/settings`,
          {
            project: { state: 'archived' },
          } as Record<string, FormDataConvertible>,
          {
            onSuccess: () => {
              notifications.show({ message: 'Project archived', color: 'red' });
              router.visit('/company/projects');
            },
            onError: () => {
              notifications.show({ message: 'Failed to archive project', color: 'red' });
            },
          },
        );
      },
    });
  };

  const [deleteOpen, setDeleteOpen] = useState(false);
  const [deleteConfirmText, setDeleteConfirmText] = useState('');

  const handleDelete = () => setDeleteOpen(true);

  const confirmDelete = () => {
    router.delete(`/company/projects/${project.id}`, {
      onSuccess: () => {
        notifications.show({ message: 'Project deleted', color: 'red' });
        router.visit('/company/projects');
      },
      onError: () => {
        notifications.show({ message: 'Failed to delete project', color: 'red' });
      },
    });
  };

  const stateConfig = STATUS_CONFIG[project.state] ?? {
    label: project.state,
    chipClass: 'statusChipDefault',
    dotClass: 'statusDotDefault',
  };

  const lastUsedLabel = project.insightsConnectionTokenLastUsedAt
    ? new Date(project.insightsConnectionTokenLastUsedAt).toLocaleString('en-US', {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
      })
    : null;

  return (
    <>
      <Head title={`Settings — ${project.name}`} />

      <Box mb={24}>
        <Text className={classes.pageTitle}>Project Settings</Text>
        <Text className={classes.pageSubtitle}>Manage project configuration and preferences</Text>
      </Box>

      <div className={classes.grid2}>
        <Stack gap="md">
          <Card p={22} withBorder radius={8}>
            <div className={classes.secLabel}>
              <IconAdjustments size={14} className={classes.secLabelIcon} />
              General
            </div>

            <form onSubmit={form.onSubmit(handleSubmit)}>
              <Stack gap="md">
                <TextInput
                  label="Project Name"
                  placeholder="Enter project name"
                  {...form.getInputProps('name')}
                  onChange={(e) => {
                    form.getInputProps('name').onChange(e);
                    setSaved(false);
                  }}
                />

                <Textarea
                  label="Description"
                  placeholder="Enter project description"
                  minRows={3}
                  {...form.getInputProps('description')}
                  onChange={(e) => {
                    form.getInputProps('description').onChange(e);
                    setSaved(false);
                  }}
                />

                <Box>
                  <Text size="sm" fw={500} mb={4}>
                    Artifacts Language
                  </Text>
                  <Text size="xs" c="dimmed" mb={6}>
                    Language AI agents use when generating artifacts and summaries
                  </Text>
                  <Select
                    data={LANGUAGE_OPTIONS}
                    {...form.getInputProps('preferredArtifactsLanguage')}
                    onChange={(v) => {
                      form.getInputProps('preferredArtifactsLanguage').onChange(v);
                      setSaved(false);
                    }}
                  />
                </Box>

                <div className={classes.saveRow}>
                  {saved && (
                    <span className={classes.savedChip}>
                      <IconCheck size={12} /> Saved
                    </span>
                  )}
                  <Button
                    type="submit"
                    size="compact-sm"
                    disabled={!form.isDirty() || !form.values.name.trim() || isSubmitting}
                    loading={isSubmitting}
                  >
                    Save Changes
                  </Button>
                </div>
              </Stack>
            </form>
          </Card>

          <Card p={22} withBorder radius={8}>
            <div className={classes.secLabel}>
              <IconChartBar size={14} className={classes.secLabelIcon} />
              Aixle Insights
            </div>

            <Stack gap="md">
              <Switch
                label="Share usage with Aixle Insights"
                description="When enabled, completed agent session tokens and cost can be pulled into Aixle Insights. Prompts, transcripts, and secrets never leave Flow."
                checked={project.shareUsageWithInsights}
                onChange={(e) => handleInsightsSharingChange(e.currentTarget.checked)}
                disabled={!project.canManageInsightsSharing || insightsSaving}
              />

              {project.canManageInsightsSharing && project.shareUsageWithInsights && (
                <Box>
                  <Text size="sm" fw={500} mb={4}>
                    Connection token
                  </Text>
                  <Text size="xs" c="dimmed" mb="sm">
                    Paste this token into an Aixle Insights Flow connector. It is shown once after generation.
                  </Text>

                  {project.insightsConnectionToken && (
                    <Alert color="yellow" mb="sm" title="Copy this token now">
                      <Group justify="space-between" align="flex-start" wrap="nowrap" gap="sm">
                        <Code style={{ wordBreak: 'break-all', flex: 1 }}>{project.insightsConnectionToken}</Code>
                        <CopyButton value={project.insightsConnectionToken}>
                          {({ copied, copy }) => (
                            <Button
                              variant="light"
                              size="compact-sm"
                              onClick={copy}
                              leftSection={copied ? <IconCheck size={14} /> : <IconCopy size={14} />}
                            >
                              {copied ? 'Copied' : 'Copy'}
                            </Button>
                          )}
                        </CopyButton>
                      </Group>
                    </Alert>
                  )}

                  <Group gap="sm">
                    <Button
                      size="compact-sm"
                      variant="default"
                      loading={tokenGenerating}
                      onClick={handleGenerateToken}
                    >
                      {project.insightsConnectionConfigured ? 'Regenerate token' : 'Generate token'}
                    </Button>
                    {project.insightsConnectionConfigured && !project.insightsConnectionToken && (
                      <Text size="xs" c="dimmed">
                        Token configured
                        {lastUsedLabel ? ` · last used ${lastUsedLabel}` : ' · not used yet'}
                      </Text>
                    )}
                  </Group>
                </Box>
              )}

              {!project.canManageInsightsSharing && (
                <Text size="xs" c="dimmed">
                  Only the project owner or a company admin can change Insights sharing.
                </Text>
              )}
            </Stack>
          </Card>
        </Stack>

        <div className={classes.colSide}>
          <Card p={22} withBorder radius={8}>
            <div className={classes.secLabel}>
              <IconInfoCircle size={14} className={classes.secLabelIcon} />
              Details
            </div>

            <div className={classes.metaGrid}>
              <Box>
                <Text className={classes.metaKey}>Status</Text>
                <span className={classes[stateConfig.chipClass]}>
                  <span className={classes[stateConfig.dotClass]} />
                  {stateConfig.label}
                </span>
              </Box>

              <Box>
                <Text className={classes.metaKey}>Created</Text>
                <Text size="sm">
                  {new Date(project.createdAt).toLocaleDateString('en-US', {
                    year: 'numeric',
                    month: 'long',
                    day: 'numeric',
                  })}
                </Text>
              </Box>

              <Box>
                <Text className={classes.metaKey}>Owner</Text>
                <Group gap="sm">
                  <Box className={classes.ownerAvatar} bg="var(--accent-dim)" c="var(--accent)">
                    {avatarInitials(project.ownerName)}
                  </Box>
                  <Box>
                    <Text size="sm" lh={1.3}>
                      {project.ownerName}
                    </Text>
                    <Text size="xs" c="dimmed" lh={1.3}>
                      {project.ownerEmail}
                    </Text>
                  </Box>
                </Group>
              </Box>

              <Box>
                <Text className={classes.metaKey}>
                  Slug <IconLock size={11} color="var(--mantine-color-dimmed)" />
                </Text>
                <Group gap="xs">
                  <Text size="sm" style={{ fontFamily: 'var(--app-font-mono)' }}>
                    {project.slug}
                  </Text>
                  <CopyButton value={project.slug}>
                    {({ copied, copy }) => (
                      <Tooltip label={copied ? 'Copied' : 'Copy slug'}>
                        <Button variant="subtle" size="compact-xs" p={4} onClick={copy}>
                          {copied ? <IconCheck size={14} /> : <IconCopy size={14} />}
                        </Button>
                      </Tooltip>
                    )}
                  </CopyButton>
                </Group>
              </Box>
            </div>
          </Card>

          <Card p={22} className={classes.dangerCard}>
            <div className={classes.secLabelDanger}>
              <IconAlertTriangle size={14} className={classes.secLabelDangerIcon} />
              Danger Zone
            </div>

            <Stack gap="lg">
              <div className={classes.dangerRow}>
                <Box>
                  <Text size="sm" fw={500}>
                    Archive this project
                  </Text>
                  <Text size="xs" c="dimmed">
                    Hide from the sidebar and prevent new sessions. Data will be preserved.
                  </Text>
                </Box>
                <Button
                  variant="outline"
                  color="red"
                  size="compact-sm"
                  leftSection={<IconArchive size={14} />}
                  onClick={handleArchive}
                  style={{ flexShrink: 0 }}
                >
                  Archive
                </Button>
              </div>

              {project.canDelete && (
                <>
                  <Divider color="red.9" />

                  <div className={classes.dangerRow}>
                    <Box>
                      <Text size="sm" fw={500}>
                        Delete this project
                      </Text>
                      <Text size="xs" c="dimmed">
                        Permanently remove this project and all of its data. This action cannot be undone.
                      </Text>
                    </Box>
                    <Button
                      variant="outline"
                      color="red"
                      size="compact-sm"
                      leftSection={<IconTrash size={14} />}
                      onClick={handleDelete}
                      style={{ flexShrink: 0 }}
                    >
                      Delete
                    </Button>
                  </div>
                </>
              )}
            </Stack>
          </Card>
        </div>
      </div>

      <Modal
        opened={deleteOpen}
        onClose={() => {
          setDeleteOpen(false);
          setDeleteConfirmText('');
        }}
        title={
          <Text fw={600} c="var(--app-danger-fg)">
            Delete project
          </Text>
        }
        centered
      >
        <Stack gap="md">
          <Text size="sm">
            This permanently deletes <b>{project.name}</b> and everything in it — sessions, assets, workflows and
            workflow runs. It cannot be undone.
          </Text>
          <Box>
            <Text size="sm" fw={500} mb={6}>
              To confirm, type the project name:
            </Text>
            <Text size="sm" c="dimmed" mb={8}>
              <code>{project.name}</code>
            </Text>
            <TextInput
              label="Project name"
              value={deleteConfirmText}
              onChange={(e) => setDeleteConfirmText(e.currentTarget.value)}
              placeholder={project.name}
              autoComplete="off"
            />
          </Box>
          <Group justify="flex-end" gap="sm">
            <Button
              variant="default"
              onClick={() => {
                setDeleteOpen(false);
                setDeleteConfirmText('');
              }}
            >
              Cancel
            </Button>
            <Button
              color="red"
              disabled={deleteConfirmText.toLowerCase() !== project.name.toLowerCase()}
              onClick={confirmDelete}
            >
              Delete project
            </Button>
          </Group>
        </Stack>
      </Modal>
    </>
  );
};

setPageLayout(SettingsPage, persistentProjectLayout);

export default SettingsPage;
