import {
  ActionIcon,
  Badge,
  Box,
  Button,
  Card,
  Center,
  Group,
  SimpleGrid,
  Text,
  TextInput,
  Tooltip,
} from '@mantine/core';
import { IconExternalLink, IconPencil, IconPencilPlus, IconSearch, IconTrash } from '@tabler/icons-react';
import { useMemo, useState } from 'react';

import { useProjectPermissions } from 'shared/lib/hooks/useProjectPermissions';

import { DeleteSkillModal } from './DeleteSkillModal';
import { ManualSkillModal } from './ManualSkillModal';
import { SkillsCatalogModal, type CatalogSkill } from './SkillsCatalogModal';

export type { CatalogSkill };

export interface Skill {
  id: number;
  name: string;
  title: string | null;
  description: string | null;
  /** Null for a hand-written skill — there is no registry package behind it. */
  package: string | null;
  source: string | null;
  sourceUrl: string | null;
  installCount: number;
  origin: 'registry' | 'manual';
  /** Present only for hand-written skills — the file the edit form loads. */
  content: string | null;
  scopeType: string | null;
  scopeId: number | null;
  scopeIndicator: string;
  /** Null for a hand-written skill. */
  registryUrl: string | null;
  createdAt: string;
  updatedAt: string;
}

interface SkillsContentProps {
  skills: Skill[];
  basePath: string;
  title: string;
  subtitle: string;
  catalogSkills: CatalogSkill[];
  catalogQuery: string;
  catalogSyncedAt: string | null;
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
  catalogSkills,
  catalogQuery,
  catalogSyncedAt,
}: SkillsContentProps) {
  const { canExecute } = useProjectPermissions();
  const [filterSearch, setFilterSearch] = useState('');
  const [deleteSkill, setDeleteSkill] = useState<Skill | null>(null);
  const [catalogOpen, setCatalogOpen] = useState(false);
  const [manualOpen, setManualOpen] = useState(false);
  // Editing reuses the authoring form: a skill IS a SKILL.md, so there is one editor.
  const [editSkill, setEditSkill] = useState<Skill | null>(null);

  const filtered = useMemo(() => {
    if (!filterSearch.trim()) return skills;
    const q = filterSearch.toLowerCase();
    return skills.filter(
      (s) =>
        (s.name?.toLowerCase().includes(q) ?? false) ||
        (s.title?.toLowerCase().includes(q) ?? false) ||
        (s.source?.toLowerCase().includes(q) ?? false),
    );
  }, [skills, filterSearch]);

  // Manual skills have no package, so they can never mark a catalog entry installed.
  const installedPackages = useMemo(
    () => new Set(skills.map((s) => s.package).filter((pkg): pkg is string => !!pkg)),
    [skills],
  );

  return (
    <Box>
      <Group justify="space-between" mb="lg">
        <Box>
          <Text fz={24} fw={600} c="var(--app-text-primary)">
            {title}
          </Text>
          <Text fz={14} c="dimmed" mt={4}>
            {subtitle}
          </Text>
        </Box>
        {canExecute && (
          <Group gap="xs">
            <Button variant="default" leftSection={<IconPencilPlus size={16} />} onClick={() => setManualOpen(true)}>
              Add manually
            </Button>
            <Button leftSection={<IconSearch size={16} />} onClick={() => setCatalogOpen(true)}>
              Browse catalog
            </Button>
          </Group>
        )}
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
          <Text fz={16} fw={500} c="var(--app-text-primary)" mt="sm">
            {filterSearch ? 'No skills match your filter' : 'No skills installed'}
          </Text>
          {!filterSearch && (
            <Text fz={13} c="dimmed" mt={4} maw={420} ta="center">
              Skills are packaged instructions an agent can load on demand during a session.
            </Text>
          )}
          {!filterSearch && canExecute && (
            <Group gap="xs" mt="md">
              <Button variant="outline" onClick={() => setCatalogOpen(true)}>
                Browse catalog
              </Button>
              <Button variant="subtle" onClick={() => setManualOpen(true)}>
                Add manually
              </Button>
            </Group>
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
                  <Text fz={15} fw={600} c="var(--app-text-primary)" ff="JetBrains Mono, monospace" truncate>
                    {skill.name}
                  </Text>
                  {skill.origin === 'manual' && (
                    <Badge color="grape" size="xs" variant="light" style={{ flexShrink: 0 }}>
                      manual
                    </Badge>
                  )}
                </Group>
                {canExecute && (
                  <Group gap={2} wrap="nowrap" style={{ flexShrink: 0 }}>
                    {/* Only hand-written skills: a registry skill's content belongs to
                        the source it names, and the next install would clobber an edit. */}
                    {skill.origin === 'manual' && (
                      <Tooltip label="Edit">
                        <ActionIcon
                          aria-label={`Edit ${skill.name}`}
                          variant="subtle"
                          size="sm"
                          color="gray"
                          onClick={() => setEditSkill(skill)}
                        >
                          <IconPencil size={16} />
                        </ActionIcon>
                      </Tooltip>
                    )}
                    <Tooltip label="Remove">
                      <ActionIcon
                        aria-label={`Remove ${skill.name}`}
                        variant="subtle"
                        size="sm"
                        color="red"
                        onClick={() => setDeleteSkill(skill)}
                      >
                        <IconTrash size={16} />
                      </ActionIcon>
                    </Tooltip>
                  </Group>
                )}
              </Group>

              {skill.title && skill.title !== skill.name && (
                <Text fz={13} fw={500} c="var(--app-text-secondary)" mb={4}>
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
                    {skill.source ?? 'written here'}
                  </Text>
                  {skill.registryUrl && (
                    <ActionIcon
                      variant="subtle"
                      size={16}
                      component="a"
                      href={skill.registryUrl}
                      target="_blank"
                      rel="noopener"
                      aria-label={`Open ${skill.name} on skills.sh`}
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

      <SkillsCatalogModal
        opened={catalogOpen}
        onClose={() => setCatalogOpen(false)}
        catalogSkills={catalogSkills}
        query={catalogQuery}
        pagePath={basePath}
        installPath={basePath}
        catalogSyncedAt={catalogSyncedAt}
        installedPackages={installedPackages}
      />
      <ManualSkillModal opened={manualOpen} onClose={() => setManualOpen(false)} basePath={basePath} />
      <ManualSkillModal opened={!!editSkill} onClose={() => setEditSkill(null)} basePath={basePath} skill={editSkill} />
      <DeleteSkillModal
        opened={!!deleteSkill}
        onClose={() => setDeleteSkill(null)}
        skill={deleteSkill}
        basePath={basePath}
      />
    </Box>
  );
}
