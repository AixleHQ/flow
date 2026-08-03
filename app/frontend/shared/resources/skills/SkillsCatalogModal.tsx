import { router } from '@inertiajs/react';
import {
  Alert,
  Avatar,
  Badge,
  Button,
  Card,
  Center,
  CloseButton,
  Group,
  Loader,
  Modal,
  SimpleGrid,
  Text,
  TextInput,
  Tooltip,
} from '@mantine/core';
import { useDebouncedCallback } from '@mantine/hooks';
import { IconAlertTriangle, IconSearch, IconSparkles } from '@tabler/icons-react';
import { useState, type FC } from 'react';

export interface AuditProvider {
  provider: string;
  risk: string | null;
  score: number | null;
  alerts: number | null;
  analyzed_at: string | null;
}

// Shapes served by CatalogSkillResource. Camel-cased on the wire by the app's
// Inertia prop transform; nested keys stay snake_case (see `analyzed_at`).
//
// Identity is `registryId`, not a database id: an entry can be a live upstream hit
// with no mirror row behind it.
export interface CatalogSkill {
  registryId: string;
  source: string;
  slug: string;
  title: string | null;
  description: string | null;
  installs: number;
  featured: boolean;
  pickerName: string;
  package: string;
  iconUrl: string | null;
  registryUrl: string;
  /** Worst verdict across providers. Null means nobody audited it — not "safe". */
  auditRisk: string | null;
  auditProviders: AuditProvider[];
}

const RISK_COLORS: Record<string, string> = {
  safe: 'teal',
  low: 'yellow',
  medium: 'orange',
  high: 'red',
  critical: 'red',
  unknown: 'gray',
};

// Providers genuinely disagree, so the tooltip names each one rather than letting a
// single badge imply consensus.
const auditSummary = (skill: CatalogSkill): string =>
  skill.auditProviders
    .map((p) => `${p.provider}: ${p.risk ?? 'unknown'}${p.score != null ? ` (score ${p.score})` : ''}`)
    .join(' · ');

interface SkillsCatalogModalProps {
  opened: boolean;
  onClose: () => void;
  catalogSkills: CatalogSkill[];
  query: string;
  /** Page path the catalog props live on — searching partial-reloads it. */
  pagePath: string;
  /** Where an install POSTs to. */
  installPath: string;
  catalogSyncedAt: string | null;
  installedPackages: Set<string>;
}

// Initials drawn locally. Every icon URL is a GitHub avatar derived from the
// registry id, so any of them can fail — a missing logo must never leave a hole in
// the grid.
const monogram = (skill: CatalogSkill): string => {
  const source = skill.title || skill.slug;
  // `split` on an empty string yields [''], so length is never 0 — an emoji-only or
  // punctuation-only name has to fall through to the '?' below, not to a blank badge.
  const words = source
    .replace(/[^\p{L}\p{N} ]/gu, ' ')
    .trim()
    .split(/\s+/)
    .filter(Boolean);
  const initials = words.length === 1 ? words[0].slice(0, 2) : (words[0] ?? '')[0] + (words[1] ?? '')[0];
  return initials?.toUpperCase() || '?';
};

// A flagged verdict interrupts the install instead of decorating it: `high` and
// `critical` are exactly the cases where one click should not be enough. An
// unrecognised label counts as flagged — the server sorts it as worst-known.
const KNOWN_RISKS = ['safe', 'low', 'medium', 'high', 'critical', 'unknown'];
const needsConfirmation = (skill: CatalogSkill): boolean => {
  const risk = skill.auditRisk;
  if (!risk || risk === 'unknown') return false;
  return risk === 'high' || risk === 'critical' || !KNOWN_RISKS.includes(risk);
};

const formatInstalls = (count: number): string => {
  if (count >= 1_000_000) return `${(count / 1_000_000).toFixed(1)}M`;
  if (count >= 1000) return `${(count / 1000).toFixed(1)}K`;
  return count.toString();
};

// Browsing the skills catalog. An empty query shows the mirrored default view;
// typing goes upstream, because skills.sh's fuzzy search is better than local
// full-text over an intentionally incomplete mirror.
export const SkillsCatalogModal: FC<SkillsCatalogModalProps> = ({
  opened,
  onClose,
  catalogSkills,
  query,
  pagePath,
  installPath,
  catalogSyncedAt,
  installedPackages,
}) => {
  const [search, setSearch] = useState(query);
  const [installing, setInstalling] = useState<string | null>(null);
  const [confirming, setConfirming] = useState<CatalogSkill | null>(null);
  // Results come from a server round trip, so the field has to say something is
  // happening; a debounced search with no feedback reads as broken.
  const [searching, setSearching] = useState(false);

  const runSearch = useDebouncedCallback((value: string) => {
    router.get(
      pagePath,
      { catalog_q: value },
      {
        preserveState: true,
        replace: true,
        only: ['catalogSkills', 'catalogQuery'],
        onFinish: () => setSearching(false),
      },
    );
  }, 300);

  const changeSearch = (value: string) => {
    setSearch(value);
    // The endpoint rejects a single character, and the server keeps showing the
    // suggested set for one — so asking would only replace a useful grid with
    // "no matches".
    const trimmed = value.trim();
    if (trimmed.length === 1) {
      setSearching(false);
      return;
    }
    setSearching(true);
    runSearch(value);
  };

  // Leaving the catalog drops the query from the URL, so reloading or sharing the
  // page does not silently reopen on a stale search instead of the default view.
  const close = () => {
    onClose();
    setConfirming(null);
    if (query) {
      router.get(pagePath, {}, { preserveState: true, replace: true, only: ['catalogSkills', 'catalogQuery'] });
    }
  };

  const install = (skill: CatalogSkill) => {
    setConfirming(null);
    setInstalling(skill.registryId);
    router.post(
      installPath,
      { skillId: skill.registryId },
      {
        preserveScroll: true,
        onFinish: () => setInstalling(null),
      },
    );
  };

  const requestInstall = (skill: CatalogSkill) => {
    if (needsConfirmation(skill)) {
      setConfirming(skill);
      return;
    }
    install(skill);
  };

  return (
    <Modal
      opened={opened}
      onClose={close}
      title="Skills catalog"
      size="90%"
      closeButtonProps={{ 'aria-label': 'Close catalog' }}
    >
      {confirming && (
        <Alert
          variant="light"
          color="red"
          icon={<IconAlertTriangle size={16} />}
          title={`${confirming.pickerName} is flagged as ${confirming.auditRisk} risk`}
          mb="md"
          withCloseButton
          onClose={() => setConfirming(null)}
        >
          <Text fz={13} mb="xs">
            {auditSummary(confirming)}. A skill runs as instructions inside your agent&apos;s context — install it only
            if you trust this publisher.
          </Text>
          <Group gap="xs">
            <Button size="xs" color="red" onClick={() => install(confirming)}>
              Install anyway
            </Button>
            <Button size="xs" variant="default" onClick={() => setConfirming(null)}>
              Cancel
            </Button>
          </Group>
        </Alert>
      )}
      <TextInput
        placeholder="Search skills — try 'playwright' or 'design'"
        aria-label="Search skills"
        leftSection={<IconSearch size={16} />}
        value={search}
        onChange={(e) => changeSearch(e.currentTarget.value)}
        rightSection={
          searching ? (
            <Loader size="xs" />
          ) : (
            search && <CloseButton size="sm" aria-label="Clear search" onClick={() => changeSearch('')} />
          )
        }
        mb="md"
      />

      {/* Deliberately not "most installed": the ordering does use install counts,
          but it leads with a curated seed and penalises publishers who ship
          twenty-five near-identical skills, so the label would claim a measurement
          the list does not follow. */}
      {catalogSkills.length > 0 && !query && (
        <Text fz={12} fw={600} c="dimmed" tt="uppercase" mb="xs" style={{ letterSpacing: 0.5 }}>
          Suggested skills
        </Text>
      )}

      {catalogSkills.length === 0 ? (
        <Center mih={200} style={{ flexDirection: 'column' }}>
          <IconSparkles size={36} color="var(--app-text-secondary)" />
          <Text fz={15} c="dimmed" mt="sm">
            {query ? `No skills match “${query}”` : 'The catalog is empty'}
          </Text>
          {query ? (
            <Button variant="subtle" size="xs" mt="sm" onClick={() => changeSearch('')}>
              Show suggested skills
            </Button>
          ) : (
            <Text fz={13} c="dimmed" mt={4} ta="center">
              It fills on the next catalog sync. You can always add a skill by hand.
            </Text>
          )}
        </Center>
      ) : (
        <SimpleGrid cols={{ base: 1, sm: 2, lg: 3 }} spacing="sm">
          {catalogSkills.map((skill) => {
            const installed = installedPackages.has(skill.package);

            return (
              <Card
                key={skill.registryId}
                padding="md"
                radius="md"
                withBorder
                style={{
                  borderColor: 'var(--app-border-default)',
                  backgroundColor: installed ? 'var(--app-bg-deep)' : 'var(--app-bg-paper)',
                  display: 'flex',
                  flexDirection: 'column',
                  minHeight: 150,
                }}
              >
                <Group justify="space-between" align="flex-start" wrap="nowrap" mb={6}>
                  <Group gap={8} wrap="nowrap" style={{ minWidth: 0, flex: 1 }}>
                    <Avatar src={skill.iconUrl} alt="" size={26} radius="sm" color="gray">
                      {monogram(skill)}
                    </Avatar>
                    <Text fz={14} fw={600} c="var(--app-text-primary)" truncate style={{ minWidth: 0 }}>
                      {skill.pickerName}
                    </Text>
                  </Group>
                  {skill.installs > 0 && (
                    <Badge size="xs" variant="light" color="gray" style={{ flexShrink: 0 }}>
                      {formatInstalls(skill.installs)} installs
                    </Badge>
                  )}
                </Group>

                <Group gap={6} wrap="nowrap" mb={4}>
                  {skill.featured && (
                    <Badge size="xs" variant="light" color="blue" title="Curated pick">
                      featured
                    </Badge>
                  )}
                  {skill.auditRisk && (
                    <Tooltip label={auditSummary(skill)} multiline w={260} withArrow>
                      <Badge size="xs" variant="light" color={RISK_COLORS[skill.auditRisk] ?? 'gray'}>
                        {skill.auditRisk === 'safe' ? 'audited' : `risk: ${skill.auditRisk}`}
                      </Badge>
                    </Tooltip>
                  )}
                  <Text fz={11} c="dimmed" ff="JetBrains Mono, monospace" truncate>
                    {skill.source}
                  </Text>
                </Group>

                <Text fz={12} c="dimmed" lineClamp={3} style={{ flex: 1 }}>
                  {skill.description || 'No description available'}
                </Text>

                <Group justify="flex-end" mt="sm">
                  {installed ? (
                    <Badge color="green" size="md" variant="light">
                      Installed
                    </Badge>
                  ) : (
                    <Button
                      size="xs"
                      variant="light"
                      color={needsConfirmation(skill) ? 'red' : undefined}
                      loading={installing === skill.registryId}
                      onClick={() => requestInstall(skill)}
                    >
                      Install
                    </Button>
                  )}
                </Group>
              </Card>
            );
          })}
        </SimpleGrid>
      )}

      {catalogSyncedAt && (
        <Text fz={11} c="dimmed" mt="md">
          Catalog last synced {new Date(catalogSyncedAt).toLocaleString()}
        </Text>
      )}
    </Modal>
  );
};
