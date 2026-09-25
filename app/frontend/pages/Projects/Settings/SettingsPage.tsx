import type { FormDataConvertible } from '@inertiajs/core';
import { Head, router, usePage } from '@inertiajs/react';
import {
  Box,
  Button,
  Card,
  CopyButton,
  Divider,
  Group,
  Modal,
  NumberInput,
  Select,
  Stack,
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
  // Empty means "no reservation of my own" — the project falls back to the
  // installation default. The budget arithmetic is the server's to judge.
  concurrency: z
    .string()
    .optional()
    .refine((v) => !v || /^[1-9]\d*$/.test(v), 'Must be a whole number greater than zero'),
});

interface ProjectSettings {
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
}

interface ConcurrencyAllocation {
  name: string;
  maxSessions: number;
}

interface Concurrency {
  /** This project's own limit, or null when it runs on the deployment default. */
  maxSessions: number | null;
  default: number;
  /** The company's own limit, shared by its projects, or null when it has none. */
  companyLimit: number | null;
  /** The most this project could be set to right now; null when there is no limit. */
  available: number | null;
  allocations: ConcurrencyAllocation[];
  canManage: boolean;
}

interface Props {
  project: ProjectSettings;
  concurrency: Concurrency;
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
  const { project, concurrency } = usePage<{ props: Props }>().props as unknown as Props;
  const pageErrors = (usePage().props as unknown as { errors?: Record<string, string> }).errors;
  const basePath = `/company/projects/${project.id}`;

  const form = useForm({
    initialValues: {
      name: project.name,
      description: project.description || '',
      preferredArtifactsLanguage: project.preferredArtifactsLanguage || 'en',
      concurrency: concurrency.maxSessions != null ? String(concurrency.maxSessions) : '',
    },
    validate: zodResolver(schema),
  });

  const [saved, setSaved] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);

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
        // Sent only when this person may set it: the key's presence is what tells
        // the server a limit was submitted at all, and an empty one clears it.
        ...(concurrency.canManage ? { concurrency: values.concurrency.trim() } : {}),
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

  return (
    <>
      <Head title={`Settings — ${project.name}`} />

      <Box mb={24}>
        <Text className={classes.pageTitle}>Project Settings</Text>
        <Text className={classes.pageSubtitle}>Manage project configuration and preferences</Text>
      </Box>

      <div className={classes.grid2}>
        {/* LEFT COLUMN: General (editable) */}
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

              <Box>
                {concurrency.canManage ? (
                  <NumberInput
                    label="Concurrent Sessions"
                    description={`A reservation: this project can always run this many sessions at once, and nothing else may occupy them. Leave empty to share the unreserved pool instead, up to ${concurrency.default} at a time.`}
                    min={1}
                    allowDecimal={false}
                    allowNegative={false}
                    placeholder={`Default (${concurrency.default})`}
                    value={form.values.concurrency}
                    error={form.errors.concurrency || pageErrors?.concurrency}
                    onChange={(v) => {
                      form.setFieldValue('concurrency', v === '' || v == null ? '' : String(v));
                      setSaved(false);
                    }}
                  />
                ) : (
                  <>
                    <Text size="sm" fw={500} mb={4}>
                      Concurrent Sessions
                    </Text>
                    <Text size="sm">
                      {concurrency.maxSessions ?? concurrency.default}
                      <Text span size="xs" c="dimmed" ml={6}>
                        {concurrency.maxSessions == null ? 'from the shared pool — ' : 'reserved — '}
                        only a company admin can change this
                      </Text>
                    </Text>
                  </>
                )}

                {concurrency.companyLimit != null && (
                  <Box mt={8}>
                    <Text size="xs" c="dimmed">
                      {concurrency.available} of the company&rsquo;s {concurrency.companyLimit} is unreserved — shared
                      by every project that has no limit of its own.
                    </Text>
                    {concurrency.allocations.length > 0 && (
                      <Text size="xs" c="dimmed">
                        Reserved: {concurrency.allocations.map((a) => `${a.name} ${a.maxSessions}`).join(', ')}
                      </Text>
                    )}
                  </Box>
                )}
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

        {/* RIGHT COLUMN: Details + Danger Zone */}
        <div className={classes.colSide}>
          {/* Details (read-only) */}
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
                  <Box className={classes.ownerAvatar} bg="var(--app-action-selected)" c="var(--app-primary)">
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

          {/* Danger Zone */}
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
