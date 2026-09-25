import { Head, Link, usePage } from '@inertiajs/react';
import { Anchor, Card, Group, SegmentedControl, Select, SimpleGrid, Stack, Text, TextInput } from '@mantine/core';
import { useDebouncedValue } from '@mantine/hooks';
import { IconSearch, IconTemplate } from '@tabler/icons-react';
import { useMemo, useState } from 'react';

import { EmptyState } from 'shared/ui';
import { PageHeader } from 'shared/ui/PageHeader';

import { KindBadge } from './components/KindBadge';
import { PublisherLabel } from './components/PublisherLabel';
import { TemplatesShell } from './components/TemplatesShell';
import { describeIncludes, KIND_LABELS, templatePath, type TemplateKind, type TemplateSummary } from './types';

interface Props {
  [key: string]: unknown;
  templates: TemplateSummary[];
  signedIn: boolean;
}

const KIND_FILTERS: TemplateKind[] = ['project', 'workflow', 'board', 'agent', 'skill', 'connector'];

function requirementLine(template: TemplateSummary): string {
  const { integrations, repositories, secrets } = template.requires;
  const parts = [
    ...integrations.map((provider) => provider.replace(/_/g, ' ')),
    repositories.length > 0
      ? `${repositories.length} ${repositories.length === 1 ? 'repository' : 'repositories'}`
      : null,
    secrets.length > 0 ? `${secrets.length} ${secrets.length === 1 ? 'secret' : 'secrets'}` : null,
  ].filter(Boolean);
  return parts.length > 0 ? `Needs ${parts.join(', ')}` : 'Nothing to connect';
}

const IndexPage = () => {
  const { templates } = usePage<Props>().props;
  const [search, setSearch] = useState('');
  const [kind, setKind] = useState<string>('all');
  const [publisher, setPublisher] = useState<string | null>(null);
  const [debouncedSearch] = useDebouncedValue(search, 200);

  const counts = useMemo(
    () => Object.fromEntries(KIND_FILTERS.map((k) => [k, templates.filter((t) => t.kind === k).length])),
    [templates],
  );

  const publishers = useMemo(() => {
    const byName = new Map(templates.map((t) => [t.publisher.name, t.publisher]));
    return [...byName.values()].sort((a, b) => a.displayName.localeCompare(b.displayName));
  }, [templates]);

  const filtered = useMemo(() => {
    const query = debouncedSearch.trim().toLowerCase();
    return templates.filter(
      (t) =>
        (kind === 'all' || t.kind === kind) &&
        (!publisher || t.publisher.name === publisher) &&
        (!query || t.name.toLowerCase().includes(query) || t.summary?.toLowerCase().includes(query)),
    );
  }, [templates, kind, publisher, debouncedSearch]);

  return (
    <TemplatesShell>
      <Head title="Templates" />
      <PageHeader
        title="Templates"
        meta={
          <Text size="sm" c="var(--app-text-tertiary)">
            {templates.length} {templates.length === 1 ? 'template' : 'templates'}
          </Text>
        }
        subtitle="Connectors, boards, workflows and whole projects, reviewed by the Flow maintainers. Secrets and connections stay yours — you add them after installing."
        mb={24}
      />

      <Group mb="lg" gap="md" wrap="wrap">
        <TextInput
          placeholder="Search templates"
          aria-label="Search templates"
          leftSection={<IconSearch size={16} />}
          value={search}
          onChange={(e) => setSearch(e.currentTarget.value)}
          w={320}
        />
        <Select
          aria-label="Publisher"
          placeholder="All publishers"
          data={publishers.map((p) => ({ value: p.name, label: p.verified ? `${p.displayName} ✓` : p.displayName }))}
          value={publisher}
          onChange={setPublisher}
          clearable
          w={200}
        />
        <SegmentedControl
          value={kind}
          onChange={setKind}
          aria-label="Template kind"
          data={[
            { value: 'all', label: `All ${templates.length}` },
            ...KIND_FILTERS.map((k) => ({ value: k, label: `${KIND_LABELS[k]}s ${counts[k]}` })),
          ]}
        />
      </Group>

      {filtered.length === 0 ? (
        <EmptyState
          icon={<IconTemplate size={22} />}
          title={templates.length === 0 ? 'No templates yet' : 'No templates match'}
          description={
            templates.length === 0
              ? 'The catalog fills from the public templates repository on the next sync.'
              : 'Try another word or kind.'
          }
        />
      ) : (
        <SimpleGrid cols={{ base: 1, sm: 2, lg: 3 }} spacing="md">
          {filtered.map((template) => (
            <Card key={template.identifier} withBorder padding="lg" radius="md">
              <Stack gap="xs" h="100%">
                <Group gap="xs">
                  <KindBadge kind={template.kind} />
                  <Anchor component={Link} href={templatePath(template)} fw={600} c="var(--app-text-primary)">
                    {template.name}
                  </Anchor>
                </Group>
                <PublisherLabel publisher={template.publisher} />
                {template.summary && (
                  <Text size="sm" c="var(--app-text-secondary)" lineClamp={3}>
                    {template.summary}
                  </Text>
                )}
                <Text size="xs" ff="var(--app-font-mono)" c="var(--app-text-secondary)">
                  {describeIncludes(template.includes)}
                </Text>
                <Group justify="space-between" mt="auto" pt="xs">
                  <Text size="xs" c="var(--app-text-tertiary)">
                    {requirementLine(template)}
                  </Text>
                  <Text size="xs" c="var(--app-text-tertiary)">
                    {template.installCount} installs here
                  </Text>
                </Group>
              </Stack>
            </Card>
          ))}
        </SimpleGrid>
      )}
    </TemplatesShell>
  );
};

export default IndexPage;
