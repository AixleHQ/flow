import { router } from '@inertiajs/react';
import { Badge, Box, Button, Group, List, Modal, Radio, ScrollArea, Stack, Text, TextInput } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconCrown, IconSearch, IconShieldLock, IconUser, IconUserPlus } from '@tabler/icons-react';
import { useMemo, useState } from 'react';

import type { OwnershipCandidate } from './ownership';

// Mount only while open: the picked member and step are taken from props once.
interface Props {
  onClose: () => void;
  projectId: number;
  projectName: string;
  ownerName: string;
  candidates: OwnershipCandidate[];
  /** Opens straight on the confirmation for this member, skipping the picker. */
  targetId?: number | null;
}

const displayName = (c: OwnershipCandidate) => c.name || c.email;
const firstName = (c: OwnershipCandidate) => displayName(c).split(' ')[0];

export function TransferOwnershipModal({
  onClose,
  projectId,
  projectName,
  ownerName,
  candidates,
  targetId = null,
}: Props) {
  const [search, setSearch] = useState('');
  const [pickedId, setPickedId] = useState<number | null>(targetId);
  const [confirming, setConfirming] = useState(targetId != null);
  const [submitting, setSubmitting] = useState(false);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return candidates;
    return candidates.filter((c) => (c.name ?? '').toLowerCase().includes(q) || c.email.toLowerCase().includes(q));
  }, [candidates, search]);

  const picked = candidates.find((c) => c.id === pickedId) ?? null;

  const transfer = () => {
    if (!picked) return;
    setSubmitting(true);
    router.patch(
      `/company/projects/${projectId}/ownership`,
      { ownership: { userId: picked.id } },
      {
        preserveScroll: true,
        onSuccess: () => onClose(),
        onError: (errors) => {
          notifications.show({
            message: Object.values(errors)[0] || 'Failed to transfer ownership',
            color: 'red',
          });
        },
        onFinish: () => setSubmitting(false),
      },
    );
  };

  const renderGroup = (label: string, rows: OwnershipCandidate[]) =>
    rows.length > 0 && (
      <Box>
        <Text size="xs" fw={600} tt="uppercase" c="dimmed" mb={6}>
          {label}
        </Text>
        <Stack gap={6}>
          {rows.map((c) => (
            <Radio.Card key={c.id} value={String(c.id)} radius="md" p="sm" aria-label={displayName(c)}>
              <Group wrap="nowrap" gap="sm">
                <Radio.Indicator />
                <Box style={{ flex: 1, minWidth: 0 }}>
                  <Text size="sm" fw={500} truncate>
                    {displayName(c)}
                  </Text>
                  <Text size="xs" c="dimmed" truncate>
                    {c.email}
                  </Text>
                </Box>
                {c.collaborator && (
                  <Badge size="sm" variant="default">
                    Collaborator
                  </Badge>
                )}
                {c.companyAdmin && (
                  <Badge size="sm" variant="light">
                    Admin
                  </Badge>
                )}
              </Group>
            </Radio.Card>
          ))}
        </Stack>
      </Box>
    );

  return (
    <Modal
      opened
      onClose={onClose}
      title={<Text fw={600}>{confirming ? 'Transfer ownership?' : 'Transfer ownership'}</Text>}
      centered
    >
      {confirming && picked ? (
        <Stack gap="md">
          <Text size="sm" c="dimmed">
            This takes effect immediately.
          </Text>
          <List spacing="xs" size="sm" center>
            <List.Item icon={<IconCrown size={16} />}>
              <b>{displayName(picked)}</b> becomes the owner of this project.
            </List.Item>
            {!picked.collaborator && (
              <List.Item icon={<IconUserPlus size={16} />}>
                {firstName(picked)} is not on this project yet and will be added as owner.
              </List.Item>
            )}
            <List.Item icon={<IconUser size={16} />}>
              <b>{ownerName}</b> stays on the project as a collaborator and keeps access.
            </List.Item>
            <List.Item icon={<IconShieldLock size={16} />}>
              Only {firstName(picked)} and company admins will be able to delete the project and manage integrations.
            </List.Item>
          </List>
          <Group justify="flex-end" gap="sm">
            {targetId != null ? (
              <Button variant="default" onClick={onClose}>
                Cancel
              </Button>
            ) : (
              <Button variant="default" onClick={() => setConfirming(false)}>
                Back
              </Button>
            )}
            <Button leftSection={<IconCrown size={14} />} onClick={transfer} loading={submitting}>
              Transfer ownership
            </Button>
          </Group>
        </Stack>
      ) : (
        <Stack gap="md">
          <Text size="sm">
            Choose a company member to own <b>{projectName}</b>. A project has exactly one owner.
          </Text>
          <TextInput
            aria-label="Search members"
            placeholder="Search by name or email…"
            leftSection={<IconSearch size={16} />}
            value={search}
            onChange={(e) => setSearch(e.currentTarget.value)}
            data-autofocus
          />
          <ScrollArea.Autosize mah={320}>
            <Radio.Group value={pickedId != null ? String(pickedId) : null} onChange={(v) => setPickedId(Number(v))}>
              <Stack gap="md">
                {renderGroup(
                  'On this project',
                  filtered.filter((c) => c.collaborator),
                )}
                {renderGroup(
                  'Company members',
                  filtered.filter((c) => !c.collaborator),
                )}
                {filtered.length === 0 && (
                  <Text size="sm" c="dimmed" ta="center" py="md">
                    {search.trim()
                      ? `No eligible members match “${search.trim()}”.`
                      : 'No eligible members in this company.'}
                  </Text>
                )}
              </Stack>
            </Radio.Group>
          </ScrollArea.Autosize>
          <Group justify="flex-end" gap="sm">
            <Button variant="default" onClick={onClose}>
              Cancel
            </Button>
            <Button disabled={!picked} onClick={() => setConfirming(true)}>
              Continue
            </Button>
          </Group>
        </Stack>
      )}
    </Modal>
  );
}
