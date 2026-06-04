import { router, usePage } from '@inertiajs/react';
import { Alert, Button, Group, Loader, Modal, Select, Stack, Textarea } from '@mantine/core';
import { useForm } from '@mantine/form';
import { IconAlertCircle } from '@tabler/icons-react';
import { zodResolver } from 'mantine-form-zod-resolver';
import { useEffect, useMemo, useState, type FC } from 'react';
import { z } from 'zod';

const schema = z.object({
  integrationId: z.string().min(1, 'Integration is required'),
  fullName: z.string().min(1, 'Repository is required'),
  sourceBranch: z.string().min(1, 'Branch is required'),
  purpose: z.string().optional(),
});

type FormData = z.infer<typeof schema>;

interface Props {
  opened: boolean;
  onClose: () => void;
  basePath: string;
  existingRepoNames: Set<string>;
}

interface Integration {
  id: number;
  name: string;
  provider: string;
  status: string;
}

interface AvailableRepo {
  fullName: string;
  defaultBranch: string;
}

interface PageProps {
  integrations?: Integration[];
  availableRepos?: AvailableRepo[];
  availableBranches?: string[];
  [key: string]: unknown;
}

export const AddRepositoryModal: FC<Props> = ({ opened, onClose, basePath, existingRepoNames }) => {
  const { integrations = [], availableRepos, availableBranches } = usePage<PageProps>().props;
  const [loading, setLoading] = useState(false);
  const [loadingRepos, setLoadingRepos] = useState(false);
  const [loadingBranches, setLoadingBranches] = useState(false);

  const form = useForm<FormData>({
    validate: zodResolver(schema),
    initialValues: {
      integrationId: '',
      fullName: '',
      sourceBranch: '',
      purpose: '',
    },
  });

  const integrationOptions = useMemo(
    () =>
      integrations.map((i) => ({
        value: String(i.id),
        label: `${i.name} (${i.provider === 'github' ? 'GitHub' : 'GitLab'})`,
      })),
    [integrations],
  );

  const repoOptions = useMemo(
    () =>
      (availableRepos ?? [])
        .filter((r) => !existingRepoNames.has(r.fullName))
        .map((r) => ({ value: r.fullName, label: r.fullName })),
    [availableRepos, existingRepoNames],
  );

  const loadRepos = (integrationId: string) => {
    setLoadingRepos(true);
    router.reload({
      data: { integration_id: integrationId },
      only: ['available_repos'],
      preserveUrl: true,
      onFinish: () => setLoadingRepos(false),
    });
  };

  const loadBranches = (integrationId: string, repoName: string) => {
    setLoadingBranches(true);
    router.reload({
      data: { integration_id: integrationId, repo: repoName },
      only: ['available_branches'],
      preserveUrl: true,
      onFinish: () => setLoadingBranches(false),
    });
  };

  const handleIntegrationChange = (value: string | null) => {
    form.setFieldValue('integrationId', value ?? '');
    form.setFieldValue('fullName', '');
    form.setFieldValue('sourceBranch', '');
    if (value) {
      loadRepos(value);
    }
  };

  const handleRepoChange = (value: string | null) => {
    form.setFieldValue('fullName', value ?? '');
    form.setFieldValue('sourceBranch', '');
    if (value && form.values.integrationId) {
      const repo = (availableRepos ?? []).find((r) => r.fullName === value);
      if (repo?.defaultBranch) {
        form.setFieldValue('sourceBranch', repo.defaultBranch);
      }
      loadBranches(form.values.integrationId, value);
    }
  };

  useEffect(() => {
    if (opened && integrationOptions.length === 1 && !form.values.integrationId) {
      const onlyIntegrationId = integrationOptions[0].value;
      form.setFieldValue('integrationId', onlyIntegrationId);
      loadRepos(onlyIntegrationId);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [opened, integrationOptions]);

  const handleClose = () => {
    form.reset();
    onClose();
  };

  const pageErrors = usePage().props.errors as Record<string, string> | undefined;
  const serverErrors = useMemo(() => {
    if (!pageErrors || Object.keys(pageErrors).length === 0) return null;
    return Object.values(pageErrors).flat().join(', ');
  }, [pageErrors]);

  const handleSubmit = (values: FormData) => {
    setLoading(true);
    router.post(
      basePath,
      {
        repository: {
          integrationId: Number(values.integrationId),
          fullName: values.fullName,
          sourceBranch: values.sourceBranch,
          purpose: values.purpose,
        },
      },
      {
        preserveScroll: true,
        onFinish: () => setLoading(false),
        onSuccess: () => handleClose(),
      },
    );
  };

  return (
    <Modal opened={opened} onClose={handleClose} title="Add Repository" centered>
      <form onSubmit={form.onSubmit(handleSubmit)}>
        <Stack gap="md">
          {serverErrors && (
            <Alert icon={<IconAlertCircle size={16} />} color="red" variant="light">
              {serverErrors}
            </Alert>
          )}
          <Select
            label="Integration"
            data={integrationOptions}
            value={form.values.integrationId}
            onChange={handleIntegrationChange}
            error={form.errors.integrationId}
            required
            placeholder={
              integrationOptions.length === 0
                ? 'No integrations available — connect one first'
                : 'Select integration...'
            }
            disabled={integrationOptions.length === 0}
          />
          <Select
            label="Repository"
            data={repoOptions}
            searchable
            value={form.values.fullName}
            onChange={handleRepoChange}
            error={form.errors.fullName}
            rightSection={loadingRepos ? <Loader size={16} /> : undefined}
            required
            placeholder={loadingRepos ? 'Loading repositories...' : 'Select repository...'}
            disabled={!form.values.integrationId || loadingRepos}
          />
          <Select
            label="Source branch"
            data={availableBranches ?? []}
            searchable
            {...form.getInputProps('sourceBranch')}
            rightSection={loadingBranches ? <Loader size={16} /> : undefined}
            required
            placeholder={loadingBranches ? 'Loading branches...' : 'Select branch...'}
            disabled={!form.values.fullName || loadingBranches}
          />
          <Textarea
            label="Purpose"
            placeholder='e.g. "Our main Rails app" or "React template for new projects"'
            description="Helps AI agents understand what this repository is used for"
            {...form.getInputProps('purpose')}
            minRows={2}
            autosize
          />
          <Group justify="flex-end" mt="sm">
            <Button variant="default" onClick={handleClose} disabled={loading}>
              Cancel
            </Button>
            <Button type="submit" loading={loading}>
              Add Repository
            </Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  );
};
