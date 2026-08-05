import { router } from '@inertiajs/react';
import { Button, Group, Modal, Select, Stack, TextInput, Textarea } from '@mantine/core';
import { useForm } from '@mantine/form';
import { zod4Resolver as zodResolver } from 'mantine-form-zod-resolver';
import { useEffect, useState, type FC } from 'react';
import { z } from 'zod';

const schema = z.object({
  sourceBranch: z.string().min(1, 'Branch is required'),
  purpose: z.string().optional(),
  description: z.string().optional(),
});

type FormData = z.infer<typeof schema>;

interface Repository {
  id: number;
  fullName: string;
  sourceBranch: string;
  purpose: string | null;
  description: string | null;
  integration: { id: number; name: string; provider: string } | null;
}

interface Props {
  repo: Repository | null;
  branches?: string[];
  basePath: string;
  onClose: () => void;
}

export const EditRepositoryModal: FC<Props> = ({ repo, branches = [], basePath, onClose }) => {
  const [loading, setLoading] = useState(false);

  const form = useForm<FormData>({
    validate: zodResolver(schema),
    initialValues: {
      sourceBranch: '',
      purpose: '',
      description: '',
    },
  });

  useEffect(() => {
    if (repo) {
      form.setValues({
        sourceBranch: repo.sourceBranch,
        purpose: repo.purpose ?? '',
        description: repo.description ?? '',
      });
    } else {
      form.reset();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [repo]);

  const handleSubmit = (values: FormData) => {
    if (!repo) return;
    setLoading(true);

    router.patch(
      `${basePath}/${repo.id}`,
      { repository: values },
      {
        preserveScroll: true,
        onFinish: () => setLoading(false),
        onSuccess: () => onClose(),
      },
    );
  };

  return (
    <Modal opened={!!repo} onClose={onClose} title={`Edit ${repo?.fullName ?? 'Repository'}`} centered>
      <form onSubmit={form.onSubmit(handleSubmit)}>
        <Stack gap="md">
          {/* Branch lists come from the integration's API; public repositories
              have none to list, so the branch stays free text there. */}
          {branches.length > 0 ? (
            <Select
              label="Source branch"
              data={branches}
              searchable
              allowDeselect={false}
              {...form.getInputProps('sourceBranch')}
              required
            />
          ) : (
            <TextInput label="Source branch" placeholder="main" {...form.getInputProps('sourceBranch')} withAsterisk />
          )}
          <Textarea
            label="Purpose"
            placeholder='e.g. "Our main Rails app" or "React template for new projects"'
            description="Helps AI agents understand what this repository is used for"
            {...form.getInputProps('purpose')}
            minRows={2}
            autosize
          />
          <Textarea label="Description" placeholder="Optional description..." {...form.getInputProps('description')} />
          <Group justify="flex-end" mt="sm">
            <Button variant="default" onClick={onClose} disabled={loading}>
              Cancel
            </Button>
            <Button type="submit" loading={loading}>
              Update
            </Button>
          </Group>
        </Stack>
      </form>
    </Modal>
  );
};
