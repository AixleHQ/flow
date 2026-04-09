import { router } from '@inertiajs/react';
import {
  ActionIcon,
  Badge,
  Box,
  Button,
  Card,
  Center,
  Group,
  Loader,
  Modal,
  SimpleGrid,
  Stack,
  Text,
  TextInput,
  Tooltip,
} from '@mantine/core';
import { useDebouncedCallback } from '@mantine/hooks';
import { IconDownload, IconExternalLink, IconSearch, IconTrash } from '@tabler/icons-react';
import { useMemo, useState } from 'react';

import { DeleteSkillModal } from './DeleteSkillModal';

export interface Skill {
  id: number;
  name: string;
  title: string | null;
  description: string | null;
  package: string;
  source: string;
  sourceUrl: string | null;
  installCount: number;
  scopeType: string | null;
  scopeId: number | null;
  scopeIndicator: string;
  registryUrl: string;
  createdAt: string;
  updatedAt: string;
}

export interface RegistrySkill {
  id: string;
  name: string;
  source: string;
  installs: number;
}

interface SkillsContentProps {
  skills: Skill[];
  basePath: string;
  title: string;
  subtitle: string;
  registryQuery: string;
  registryResults: RegistrySkill[];
}

function formatInstalls(count: number): string {
  if (count >= 1_000_000) return `${(count / 1_000_000).toFixed(1)}M`;
  if (count >= 1000) return `${(count / 1000).toFixed(1)}K`;
  return count.toString();
}

export function SkillsContent({
  skills,
  basePath,
  title,
  subtitle,
  registryQuery,
  registryResults,
}: SkillsContentProps) {
  const [filterSearch, setFilterSearch] = useState('');
  const [deleteSkill, setDeleteSkill] = useState<Skill | null>(null);
  const [searchModalOpen, setSearchModalOpen] = useState(false);

  const filtered = useMemo(() => {
    if (!filterSearch.trim()) return skills;
    const q = filterSearch.toLowerCase();
    return skills.filter(
      (s) =>
        s.name.toLowerCase().includes(q) ||
        (s.title?.toLowerCase().includes(q) ?? false) ||
        s.source.toLowerCase().includes(q),
    );
  }, [skills, filterSearch]);

  const installedPackages = useMemo(() => new Set(skills.map((s) => s.package)), [skills]);

  return (
    <Box>
      <Group justify="space-between" mb="lg">
        <Box>
          <Text fz={24} fw={600} c="white">
            {title}
          </Text>
          <Text fz={14} c="dimmed" mt={4}>
            {subtitle}
          </Text>
        </Box>
        <Button leftSection={<IconSearch size={16} />} onClick={() => setSearchModalOpen(true)}>
          Add from Registry
        </Button>
      </Group>

      <TextInput
        placeholder="Filter installed skills..."
        leftSection={<IconSearch size={16} />}
        value={filterSearch}
        onChange={(e) => setFilterSearch(e.currentTarget.value)}
        mb="lg"
        maw={300}
      />

      {filtered.length === 0 ? (
        <Center
          mih={300}
          style={{
            border: '1px solid var(--app-border-default)',
            borderRadius: 'var(--mantine-radius-md)',
            backgroundColor: 'var(--app-bg-paper)',
            flexDirection: 'column',
          }}
        >
          <Text fz={48}>🔧</Text>
          <Text fz={16} c="dimmed" mt="sm">
            {filterSearch ? 'No skills match your filter' : 'No skills installed'}
          </Text>
          {!filterSearch && (
            <Button variant="outline" mt="sm" onClick={() => setSearchModalOpen(true)}>
              Browse skills.sh registry
            </Button>
          )}
        </Center>
      ) : (
        <SimpleGrid cols={{ base: 1, sm: 2, lg: 3 }} spacing="md">
          {filtered.map((skill) => (
            <Card
              key={skill.id}
              padding="lg"
              radius="md"
              withBorder
              style={{
                borderColor: 'var(--app-border-default)',
                backgroundColor: 'var(--app-bg-paper)',
                display: 'flex',
                flexDirection: 'column',
                minHeight: 160,
              }}
            >
              <Group justify="space-between" align="flex-start" wrap="nowrap" mb={8}>
                <Group gap={8} align="center" style={{ minWidth: 0, flex: 1 }}>
                  <Text fz={15} fw={600} c="white" ff="JetBrains Mono, monospace" truncate>
                    {skill.name}
                  </Text>
                  <Badge
                    color={skill.scopeIndicator === 'company' ? 'blue' : 'teal'}
                    size="xs"
                    variant="light"
                    style={{ flexShrink: 0 }}
                  >
                    {skill.scopeIndicator}
                  </Badge>
                </Group>
                <Tooltip label="Remove">
                  <ActionIcon
                    variant="subtle"
                    size="sm"
                    color="red"
                    onClick={() => setDeleteSkill(skill)}
                    style={{ flexShrink: 0 }}
                  >
                    <IconTrash size={16} />
                  </ActionIcon>
                </Tooltip>
              </Group>

              {skill.title && skill.title !== skill.name && (
                <Text fz={13} fw={500} c="var(--mantine-color-gray-4)" mb={4}>
                  {skill.title}
                </Text>
              )}

              <Text fz={12} c="dimmed" lineClamp={4} style={{ flex: 1 }}>
                {skill.description || 'No description available'}
              </Text>

              <Group
                justify="space-between"
                align="center"
                mt="md"
                pt={8}
                style={{ borderTop: '1px solid var(--app-border-default)' }}
              >
                <Group gap={4} align="center">
                  <Text fz={11} c="dimmed" ff="JetBrains Mono, monospace">
                    {skill.source}
                  </Text>
                  {skill.registryUrl && (
                    <ActionIcon
                      variant="subtle"
                      size={16}
                      component="a"
                      href={skill.registryUrl}
                      target="_blank"
                      rel="noopener"
                    >
                      <IconExternalLink size={10} />
                    </ActionIcon>
                  )}
                </Group>
                {skill.installCount > 0 && (
                  <Text fz={11} c="dimmed">
                    {formatInstalls(skill.installCount)} installs
                  </Text>
                )}
              </Group>
            </Card>
          ))}
        </SimpleGrid>
      )}

      <RegistrySearchModal
        opened={searchModalOpen}
        onClose={() => setSearchModalOpen(false)}
        basePath={basePath}
        installedPackages={installedPackages}
        initialQuery={registryQuery}
        results={registryResults}
      />
      <DeleteSkillModal
        opened={!!deleteSkill}
        onClose={() => setDeleteSkill(null)}
        skill={deleteSkill}
        basePath={basePath}
      />
    </Box>
  );
}

interface RegistrySearchModalProps {
  opened: boolean;
  onClose: () => void;
  basePath: string;
  installedPackages: Set<string>;
  initialQuery: string;
  results: RegistrySkill[];
}

function RegistrySearchModal({
  opened,
  onClose,
  basePath,
  installedPackages,
  initialQuery,
  results,
}: RegistrySearchModalProps) {
  const [query, setQuery] = useState(initialQuery);
  const [installing, setInstalling] = useState<string | null>(null);
  const [searching, setSearching] = useState(false);

  const sortedResults = useMemo(() => [...results].sort((a, b) => b.installs - a.installs), [results]);

  const debouncedSearch = useDebouncedCallback((q: string) => {
    setSearching(true);
    router.reload({
      data: { q: q || undefined },
      only: ['registryQuery', 'registryResults'],
      onFinish: () => setSearching(false),
    });
  }, 400);

  const handleQueryChange = (value: string) => {
    setQuery(value);
    debouncedSearch(value);
  };

  const handleInstall = (skillId: string) => {
    setInstalling(skillId);
    router.post(
      basePath,
      { skillId },
      {
        preserveScroll: true,
        onFinish: () => {
          setInstalling(null);
          setQuery('');
          router.reload({
            data: { q: undefined },
            only: ['skills', 'registryQuery', 'registryResults'],
          });
        },
      },
    );
  };

  const handleClose = () => {
    onClose();
    if (query) {
      router.reload({ data: { q: undefined }, only: ['registryQuery', 'registryResults'] });
    }
  };

  const packageFromId = (id: string) => {
    const parts = id.split('/');
    if (parts.length >= 3) return `${parts[0]}/${parts[1]}@${parts.slice(2).join('/')}`;
    return id;
  };

  return (
    <Modal
      opened={opened}
      onClose={handleClose}
      title={
        <Text fz={18} fw={600} c="white">
          Search skills.sh Registry
        </Text>
      }
      size="xl"
      styles={{
        body: { minHeight: 500 },
      }}
    >
      <Stack gap="md">
        <TextInput
          placeholder="Search skills... (e.g. mantine, react, testing, nextjs)"
          leftSection={<IconSearch size={16} />}
          rightSection={searching ? <Loader size={14} /> : undefined}
          value={query}
          onChange={(e) => handleQueryChange(e.currentTarget.value)}
          autoFocus
          size="md"
        />

        {sortedResults.length > 0 && (
          <Box
            style={{
              maxHeight: 480,
              overflowY: 'auto',
            }}
          >
            <Stack gap="xs">
              {sortedResults.map((skill) => {
                const pkg = packageFromId(skill.id);
                const isInstalled = installedPackages.has(pkg);

                return (
                  <Card
                    key={skill.id}
                    padding="md"
                    radius="md"
                    withBorder
                    style={{
                      borderColor: 'var(--app-border-default)',
                      backgroundColor: isInstalled ? 'var(--app-bg-deep)' : 'var(--app-bg-paper)',
                    }}
                  >
                    <Group justify="space-between" align="flex-start" wrap="nowrap">
                      <Box style={{ minWidth: 0, flex: 1 }}>
                        <Group gap={8} align="center">
                          <Text fz={15} fw={600} c="white" ff="JetBrains Mono, monospace">
                            {skill.name}
                          </Text>
                          <Badge size="xs" variant="light" color="gray">
                            {formatInstalls(skill.installs)} installs
                          </Badge>
                        </Group>
                        <Group gap={4} mt={6} align="center">
                          <Text fz={12} c="dimmed" ff="JetBrains Mono, monospace">
                            {skill.id}
                          </Text>
                          <ActionIcon
                            variant="subtle"
                            size={16}
                            component="a"
                            href={`https://skills.sh/${skill.id}`}
                            target="_blank"
                            rel="noopener"
                          >
                            <IconExternalLink size={10} />
                          </ActionIcon>
                        </Group>
                      </Box>
                      <Box pt={2}>
                        {isInstalled ? (
                          <Badge color="green" size="md" variant="light">
                            Installed
                          </Badge>
                        ) : (
                          <Button
                            size="xs"
                            variant="light"
                            leftSection={<IconDownload size={14} />}
                            loading={installing === skill.id}
                            onClick={() => handleInstall(skill.id)}
                          >
                            Install
                          </Button>
                        )}
                      </Box>
                    </Group>
                  </Card>
                );
              })}
            </Stack>
          </Box>
        )}

        {!searching && initialQuery && sortedResults.length === 0 && (
          <Center py="xl" mih={300}>
            <Stack align="center" gap="xs">
              <Text fz={14} c="dimmed">
                No skills found for &ldquo;{initialQuery}&rdquo;
              </Text>
              <Text fz={12} c="dimmed">
                Try different keywords or browse{' '}
                <Text
                  span
                  c="blue"
                  component="a"
                  href="https://skills.sh"
                  target="_blank"
                  rel="noopener"
                  td="underline"
                >
                  skills.sh
                </Text>
              </Text>
            </Stack>
          </Center>
        )}

        {!initialQuery && (
          <Center py="xl" mih={300}>
            <Stack align="center" gap="xs">
              <Text fz={36}>🔍</Text>
              <Text fz={14} c="dimmed">
                Search the{' '}
                <Text
                  span
                  c="blue"
                  component="a"
                  href="https://skills.sh"
                  target="_blank"
                  rel="noopener"
                  td="underline"
                >
                  skills.sh
                </Text>{' '}
                registry to find and install agent skills
              </Text>
              <Text fz={12} c="dimmed" maw={400} ta="center">
                Skills teach your AI agent best practices, framework knowledge, and project-specific conventions.
                Installed skills are applied automatically at session start.
              </Text>
            </Stack>
          </Center>
        )}
      </Stack>
    </Modal>
  );
}
