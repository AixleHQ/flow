import { Head, router, usePage } from '@inertiajs/react';
import {
  Anchor,
  Badge,
  Button,
  Card,
  Group,
  PasswordInput,
  Progress,
  Select,
  Stack,
  Text,
  Title,
  Typography,
} from '@mantine/core';
import { useState } from 'react';
import Markdown from 'react-markdown';

import { AuthLayout } from 'layouts/AuthLayout';

import { PageHeader } from 'shared/ui/PageHeader';

interface SetupItem {
  id: number;
  kind: 'secret' | 'integration' | 'repository' | 'oauth' | 'probe' | 'trigger' | 'board';
  ref: string;
  status: 'pending' | 'done' | 'failed' | 'dismissed';
  label: string;
  detail: Record<string, unknown>;
}

interface Props {
  project: { id: number; name: string };
  install: { id: number; name: string; version: number; setup: string | null };
  items: SetupItem[];
  repositories: { id: number; fullName: string }[];
  integrationsPath: string;
  mcpServersPath: string;
}

const STATUS_COLORS: Record<SetupItem['status'], string> = {
  pending: 'yellow',
  failed: 'red',
  done: 'green',
  dismissed: 'gray',
};

function ItemActions({ item, props }: { item: SetupItem; props: Props }) {
  const [value, setValue] = useState('');
  const [repositoryId, setRepositoryId] = useState<string | null>(null);
  const url = `/company/projects/${props.project.id}/template_installs/${props.install.id}/setup_items/${item.id}`;
  const act = (operation: string, data: Record<string, unknown> = {}) =>
    router.patch(url, { operation, ...data }, { preserveScroll: true });

  if (item.status === 'done' || item.status === 'dismissed') return null;

  return (
    <Group gap="xs" wrap="wrap">
      {item.kind === 'secret' && (
        <>
          <PasswordInput
            aria-label={`Value for ${String(item.detail.name)}`}
            placeholder="Paste the value"
            value={value}
            onChange={(e) => setValue(e.currentTarget.value)}
            w={260}
            size="xs"
            autoComplete="off"
          />
          <Button size="xs" disabled={!value} onClick={() => act('add_secret', { value })}>
            Save
          </Button>
        </>
      )}
      {item.kind === 'repository' &&
        (props.repositories.length > 0 ? (
          <>
            <Select
              aria-label="Repository"
              placeholder="Choose a repository"
              data={props.repositories.map((r) => ({ value: String(r.id), label: r.fullName }))}
              value={repositoryId}
              onChange={setRepositoryId}
              size="xs"
              w={260}
            />
            <Button
              size="xs"
              disabled={!repositoryId}
              onClick={() => act('attach_repository', { repository_id: repositoryId })}
            >
              Attach
            </Button>
          </>
        ) : (
          <Text size="xs" c="var(--app-text-tertiary)">
            Add a repository to the project first.
          </Text>
        ))}
      {item.kind === 'integration' && (
        <Button size="xs" component="a" href={props.integrationsPath} variant="light">
          Connect
        </Button>
      )}
      {(item.kind === 'oauth' || item.kind === 'probe') && (
        <>
          {item.kind === 'oauth' && (
            <Button size="xs" component="a" href={props.mcpServersPath} variant="light">
              Sign in
            </Button>
          )}
          <Button size="xs" variant="subtle" onClick={() => act('recheck')}>
            Check again
          </Button>
        </>
      )}
      {item.kind === 'trigger' && !item.detail.missing && (
        <Button size="xs" onClick={() => act('activate')}>
          Activate
        </Button>
      )}
      <Button size="xs" variant="subtle" color="gray" onClick={() => act('dismiss')}>
        Dismiss
      </Button>
    </Group>
  );
}

const ShowPage = () => {
  const props = usePage().props as unknown as Props;
  const { install, items } = props;
  const finished = items.filter((i) => i.status === 'done' || i.status === 'dismissed').length;

  return (
    <AuthLayout>
      <Head title={`Set up ${install.name}`} />
      <PageHeader
        title={`Set up ${install.name}`}
        subtitle={`Installed from the template catalog (version ${install.version}). What is left before it runs on its own.`}
        mb={20}
      />
      <Stack gap="lg" maw={860}>
        {items.length > 0 && (
          <Group gap="sm">
            <Progress value={(finished / items.length) * 100} w={240} aria-label="Setup progress" />
            <Text size="sm" c="var(--app-text-secondary)">
              {finished} of {items.length} done
            </Text>
          </Group>
        )}
        {install.setup && (
          <Card withBorder padding="lg" radius="md">
            <Typography>
              <Markdown>{install.setup}</Markdown>
            </Typography>
          </Card>
        )}
        {items.length === 0 ? (
          <Text c="var(--app-text-secondary)">Nothing left to set up.</Text>
        ) : (
          <Card withBorder padding={0} radius="md">
            {items.map((item) => (
              <Stack key={item.id} gap={6} p="md" style={{ borderBottom: '1px solid var(--app-border-subtle)' }}>
                <Group justify="space-between">
                  <Title order={3} size="sm">
                    {item.label}
                  </Title>
                  <Badge color={STATUS_COLORS[item.status]} variant="light" tt="none">
                    {item.status}
                  </Badge>
                </Group>
                {typeof item.detail.description === 'string' && (
                  <Text size="xs" c="var(--app-text-tertiary)">
                    {item.detail.description}
                  </Text>
                )}
                {typeof item.detail.missing === 'string' && (
                  <Text size="xs" c="var(--app-warning-fg)">
                    {item.detail.missing}
                  </Text>
                )}
                <ItemActions item={item} props={props} />
              </Stack>
            ))}
          </Card>
        )}
        <Anchor href={`/company/projects/${props.project.id}/overview`} size="sm">
          Go to the project
        </Anchor>
      </Stack>
    </AuthLayout>
  );
};

export default ShowPage;
