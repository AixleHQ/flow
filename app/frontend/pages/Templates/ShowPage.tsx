import { Head, Link, usePage } from '@inertiajs/react';
import {
  Alert,
  Anchor,
  Badge,
  Button,
  Card,
  Grid,
  Group,
  List,
  Stack,
  Tabs,
  Text,
  Title,
  Typography,
} from '@mantine/core';
import { IconAlertTriangle } from '@tabler/icons-react';
import type { ReactNode } from 'react';
import Markdown from 'react-markdown';

import { PageHeader } from 'shared/ui/PageHeader';

import { KindBadge } from './components/KindBadge';
import { PublisherLabel } from './components/PublisherLabel';
import { TemplatesShell } from './components/TemplatesShell';
import type { TemplateDetail } from './types';

interface Props {
  [key: string]: unknown;
  template: TemplateDetail;
  installPath: string | null;
  signedIn: boolean;
}

function Section({ title, count, children }: { title: string; count?: number; children: ReactNode }) {
  return (
    <Stack gap={6} py="sm" style={{ borderBottom: '1px solid var(--app-border-subtle)' }}>
      <Group gap="xs">
        <Title order={3} size="sm">
          {title}
        </Title>
        {count !== undefined && (
          <Text size="xs" ff="var(--app-font-mono)" c="var(--app-text-tertiary)">
            {count}
          </Text>
        )}
      </Group>
      {children}
    </Stack>
  );
}

function Chips({ items }: { items: string[] }) {
  return (
    <Group gap={6}>
      {items.map((item) => (
        <Badge key={item} variant="outline" color="gray" radius="sm" tt="none" fw={400} ff="var(--app-font-mono)">
          {item}
        </Badge>
      ))}
    </Group>
  );
}

function WhatGetsCreated({ template }: { template: TemplateDetail }) {
  const { contents } = template;
  const pieces = [
    ...contents.skills.map((s) => `skill · ${s.name}${s.fromRegistry ? ' (registry snapshot)' : ''}`),
    ...contents.tools.map((t) => `tool · ${t.name}${t.platform ? ' (built in)' : ''}`),
    ...contents.mcpServers.map((m) => `MCP · ${m.name}${m.builtIn ? ' (built in)' : ''}`),
  ];
  return (
    <Card withBorder padding="md" radius="md">
      {template.boardColumns.length > 0 && (
        <Section title="Board" count={template.boardColumns.length}>
          <Chips items={template.boardColumns} />
        </Section>
      )}
      {contents.agents.length > 0 && (
        <Section title="Agents" count={contents.agents.length}>
          <Chips items={contents.agents} />
        </Section>
      )}
      {contents.workflows.length > 0 && (
        <Section title="Workflows" count={contents.workflows.length}>
          {contents.workflows.map((workflow) => (
            <Text key={workflow.name} size="sm" ff="var(--app-font-mono)">
              <Text span fw={600} inherit>
                {workflow.name}
              </Text>{' '}
              {workflow.steps.join(' → ')}
            </Text>
          ))}
        </Section>
      )}
      {pieces.length > 0 && (
        <Section title="Skills, tools, connectors" count={pieces.length}>
          <Chips items={pieces} />
        </Section>
      )}
      {contents.triggers.length > 0 && (
        <Section title="Triggers" count={contents.triggers.length}>
          <Text size="xs" c="var(--app-text-tertiary)">
            Installed inactive — you activate them from the setup checklist.
          </Text>
          <Chips items={contents.triggers.map((t) => `${t.kind} · ${t.column ?? t.cron ?? t.workflow}`)} />
        </Section>
      )}
      {contents.variables.length > 0 && (
        <Section title="Variables" count={contents.variables.length}>
          <Chips items={contents.variables} />
        </Section>
      )}
      <Section title="Not included">
        <Text size="sm" c="var(--app-text-secondary)">
          Cards, comments, runs, secret values, integrations and repositories. Variables come with their values; secrets
          only by name.
        </Text>
      </Section>
    </Card>
  );
}

function Requirements({ template }: { template: TemplateDetail }) {
  const { integrations, repositories, secrets } = template.requires;
  const rows = [
    ...integrations.map((p) => ({ label: `${p.replace(/_/g, ' ')} integration`, when: 'checklist' })),
    ...repositories.map((r) => ({ label: `A repository${r.purpose ? ` — ${r.purpose}` : ''}`, when: 'checklist' })),
    ...secrets.map((s) => ({ label: s.name, when: s.promptAtInstall ? 'at install' : 'checklist' })),
    ...template.inputs.map((i) => ({ label: i.label, when: 'at install' })),
  ];
  if (rows.length === 0) {
    return (
      <Text size="sm" c="var(--app-text-secondary)">
        Nothing to connect — it runs after install.
      </Text>
    );
  }
  return (
    <List spacing={6} size="sm">
      {rows.map((row) => (
        <List.Item key={row.label}>
          <Group justify="space-between" gap="xs" wrap="nowrap">
            <Text size="sm">{row.label}</Text>
            <Text size="xs" ff="var(--app-font-mono-label)" c="var(--app-text-tertiary)" tt="uppercase">
              {row.when}
            </Text>
          </Group>
        </List.Item>
      ))}
    </List>
  );
}

const ShowPage = () => {
  const { template, installPath, signedIn } = usePage<Props>().props;

  return (
    <TemplatesShell>
      <Head title={`${template.name} — Templates`} />
      <Anchor component={Link} href="/templates" size="sm" c="var(--app-text-tertiary)">
        Templates
      </Anchor>
      <Grid mt="xs" gap="xl">
        <Grid.Col span={{ base: 12, md: 8 }}>
          <Group gap="xs" mb={6}>
            <KindBadge kind={template.kind} />
            <PublisherLabel publisher={template.publisher} />
          </Group>
          <PageHeader
            title={template.name}
            subtitle={template.summary ?? undefined}
            meta={
              <Text size="xs" ff="var(--app-font-mono)" c="var(--app-text-tertiary)">
                {template.identifier} · v{template.version} · {template.commitSha.slice(0, 7)} · {template.installCount}{' '}
                installs here
              </Text>
            }
          />
          {template.revoked && (
            <Alert color="red" icon={<IconAlertTriangle size={16} />} mb="md" title="Withdrawn">
              {template.revocationReason}
            </Alert>
          )}
          <Tabs defaultValue="contents">
            <Tabs.List mb="md">
              <Tabs.Tab value="contents">What gets created</Tabs.Tab>
              {template.readme && <Tabs.Tab value="readme">Readme</Tabs.Tab>}
              {template.setup && <Tabs.Tab value="setup">Setup</Tabs.Tab>}
            </Tabs.List>
            <Tabs.Panel value="contents">
              <WhatGetsCreated template={template} />
            </Tabs.Panel>
            {template.readme && (
              <Tabs.Panel value="readme">
                <Typography>
                  <Markdown>{template.readme}</Markdown>
                </Typography>
              </Tabs.Panel>
            )}
            {template.setup && (
              <Tabs.Panel value="setup">
                <Typography>
                  <Markdown>{template.setup}</Markdown>
                </Typography>
              </Tabs.Panel>
            )}
          </Tabs>
        </Grid.Col>
        <Grid.Col span={{ base: 12, md: 4 }}>
          <Card withBorder padding="lg" radius="md" style={{ position: 'sticky', top: 20 }}>
            <Stack gap="md">
              <Title order={2} size="h4">
                Before you install
              </Title>
              <Requirements template={template} />
              {template.runsThirdPartyImages && (
                <Alert color="yellow" icon={<IconAlertTriangle size={16} />} p="sm">
                  Runs a third-party container image and third-party prompt text. Reviewed and pinned by digest — still
                  read it.
                </Alert>
              )}
              {installPath && (
                <Button component="a" href={installPath} fullWidth>
                  {signedIn ? 'Install' : 'Sign in to install'}
                </Button>
              )}
              <Text size="xs" c="var(--app-text-tertiary)" ta="center">
                {template.kind === 'project'
                  ? 'Installs as a new project, owned by you.'
                  : 'Installs into a project you choose, or a new one.'}
              </Text>
            </Stack>
          </Card>
        </Grid.Col>
      </Grid>
    </TemplatesShell>
  );
};

export default ShowPage;
