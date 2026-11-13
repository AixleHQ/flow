import { Head, router, usePage } from '@inertiajs/react';
import {
  ActionIcon,
  Avatar,
  Badge,
  Box,
  Button,
  Group,
  Paper,
  Select,
  Stack,
  Text,
  TextInput,
  Title,
  Tooltip,
} from '@mantine/core';
import { modals } from '@mantine/modals';
import { IconArrowDown, IconArrowUp, IconPlus, IconTrash, IconUsersGroup, IconX } from '@tabler/icons-react';
import { useState } from 'react';

import type { Project, ProjectTeam } from '@/types/generated';

import { formatMonthDay } from 'shared/lib/formatDate';
import { useUnsavedChanges } from 'shared/lib/unsaved-changes/useUnsavedChanges';
import { companyProjectTeamPath, companyProjectTeamsPath, leaveCompanyProjectTeamPath } from 'shared/routes';
import type { SharedProps } from 'shared/ui';
import { EmptyState } from 'shared/ui/EmptyState';
import { PageHeader } from 'shared/ui/PageHeader';
import { ResourceDrawer } from 'shared/ui/ResourceDrawer';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

type Strategy = ProjectTeam['strategy'];

export interface TeamCandidate {
  id: number;
  name: string;
  agentConnected: boolean;
  excludedFromTeams: boolean;
}

interface Props extends SharedProps {
  project: Project;
  teams: ProjectTeam[];
  candidates: TeamCandidate[];
  canManage: boolean;
}

const STRATEGY_OPTIONS: { value: Strategy; label: string; description: string }[] = [
  { value: 'priority', label: 'Priority', description: 'First member who can take the run' },
  { value: 'round_robin', label: 'Round robin', description: 'Next member after the last one picked' },
  { value: 'most_remaining', label: 'Most quota left', description: 'The member with the most agent quota left' },
];

const strategyLabel = (strategy: Strategy) => STRATEGY_OPTIONS.find((o) => o.value === strategy)?.label ?? strategy;

interface TeamForm {
  name: string;
  strategy: Strategy;
  memberIds: number[];
}

const EMPTY_FORM: TeamForm = { name: '', strategy: 'priority', memberIds: [] };

const sameForm = (a: TeamForm, b: TeamForm) =>
  a.name === b.name && a.strategy === b.strategy && a.memberIds.join(',') === b.memberIds.join(',');

type TeamMember = ProjectTeam['members'][number];

const STATUS_STYLE: Record<TeamMember['status']['state'], { color: string; label: (m: TeamMember) => string }> = {
  ready: { color: 'green', label: () => 'Ready' },
  on_hold: {
    color: 'orange',
    label: (m) => (m.status.until ? `On hold until ${formatMonthDay(m.status.until)}` : 'On hold'),
  },
  signed_out: { color: 'red', label: () => 'Login expired' },
  unavailable: { color: 'gray', label: () => "Can't take runs" },
};

function MemberStatus({ member }: { member: TeamMember }) {
  const style = STATUS_STYLE[member.status.state];
  const badge = (
    <Badge size="sm" variant="light" color={style.color} radius="xl" tt="none" fw={500}>
      {style.label(member)}
    </Badge>
  );
  return member.status.detail ? <Tooltip label={member.status.detail}>{badge}</Tooltip> : badge;
}

function usedBy(team: ProjectTeam): string {
  const parts = team.triggers.map((t) => t.workflowName ?? t.name ?? `Trigger #${t.id}`);
  if (team.taskCount > 0) parts.push(`${team.taskCount} card${team.taskCount === 1 ? '' : 's'}`);
  return parts.length > 0 ? parts.join(' · ') : 'Not used yet';
}

function TeamCard({
  team,
  currentUserId,
  canManage,
  onEdit,
  onLeave,
}: {
  team: ProjectTeam;
  currentUserId: number | undefined;
  canManage: boolean;
  onEdit: () => void;
  onLeave: () => void;
}) {
  const isMember = team.members.some((m) => m.id === currentUserId);
  const titleId = `team-${team.id}-name`;

  return (
    <Paper
      component="section"
      aria-labelledby={titleId}
      withBorder
      radius="md"
      p="lg"
      style={{ display: 'flex', flexDirection: 'column', gap: 'var(--mantine-spacing-md)' }}
    >
      <Group justify="space-between" align="baseline" wrap="nowrap">
        <Title order={3} size="h4" id={titleId}>
          {team.name}
        </Title>
        <Text size="xs" c="dimmed">
          {strategyLabel(team.strategy)}
        </Text>
      </Group>

      {team.members.length === 0 ? (
        <Text size="sm" c="dimmed">
          No members yet
        </Text>
      ) : (
        <Stack gap="sm" role="list" aria-label={`${team.name} members`}>
          {team.members.map((member, index) => (
            <Group key={member.id} gap="sm" wrap="nowrap" role="listitem">
              <Text size="xs" c="dimmed" w={12} ta="right">
                {index + 1}
              </Text>
              <Avatar size={30} radius="xl" color="initials" name={member.name} />
              <Text size="sm" style={{ flex: 1, minWidth: 0 }} truncate>
                {member.name}
                {member.id === currentUserId && (
                  <Text span size="xs" c="dimmed">
                    {' '}
                    · you
                  </Text>
                )}
              </Text>
              {team.nextMemberId === member.id && (
                <Tooltip label="The next run goes to them">
                  <Badge size="sm" variant="outline" color="var(--app-primary)" radius="sm">
                    Next
                  </Badge>
                </Tooltip>
              )}
              <MemberStatus member={member} />
            </Group>
          ))}
        </Stack>
      )}

      <Group
        justify="space-between"
        wrap="wrap"
        gap="sm"
        mt="auto"
        pt="sm"
        style={{ borderTop: '1px solid var(--app-border-default)' }}
      >
        <Text size="sm" c="dimmed" style={{ minWidth: 0 }}>
          {usedBy(team)}
        </Text>
        <Group gap="xs">
          {isMember && (
            <Button variant="default" size="xs" onClick={onLeave} aria-label={`Leave ${team.name}`}>
              Leave
            </Button>
          )}
          {canManage && (
            <Button variant="default" size="xs" onClick={onEdit} aria-label={`Edit ${team.name}`}>
              Edit
            </Button>
          )}
        </Group>
      </Group>
    </Paper>
  );
}

const TeamsPage = () => {
  const { project, teams, candidates, canManage, currentUser } = usePage<Props>().props;
  const [editing, setEditing] = useState<ProjectTeam | 'new' | null>(null);
  const [initial, setInitial] = useState<TeamForm>(EMPTY_FORM);
  const [form, setForm] = useState<TeamForm>(EMPTY_FORM);
  const [saving, setSaving] = useState(false);
  const [addingId, setAddingId] = useState<string | null>(null);

  const candidateById = new Map(candidates.map((c) => [c.id, c]));
  const memberName = (id: number) =>
    candidateById.get(id)?.name ?? teams.flatMap((t) => t.members).find((m) => m.id === id)?.name ?? `User #${id}`;

  const openNew = () => {
    setInitial(EMPTY_FORM);
    setForm(EMPTY_FORM);
    setEditing('new');
  };

  const openEdit = (team: ProjectTeam) => {
    const values = { name: team.name, strategy: team.strategy, memberIds: team.members.map((m) => m.id) };
    setInitial(values);
    setForm(values);
    setEditing(team);
  };

  const handleClose = () => {
    setEditing(null);
    setAddingId(null);
  };
  const requestClose = useUnsavedChanges({
    opened: editing !== null,
    dirty: !sameForm(form, initial),
    saving,
    onClose: handleClose,
  });

  const addMember = (value: string | null) => {
    if (!value) return;
    setForm((f) => ({ ...f, memberIds: [...f.memberIds, Number(value)] }));
    setAddingId(null);
  };

  const moveMember = (index: number, offset: -1 | 1) => {
    setForm((f) => {
      const ids = [...f.memberIds];
      const target = index + offset;
      [ids[index], ids[target]] = [ids[target], ids[index]];
      return { ...f, memberIds: ids };
    });
  };

  const removeMember = (id: number) => setForm((f) => ({ ...f, memberIds: f.memberIds.filter((m) => m !== id) }));

  const handleSave = () => {
    if (!form.name.trim()) return;
    setSaving(true);
    const payload = { team: { name: form.name.trim(), strategy: form.strategy, memberIds: form.memberIds } };
    const options = { preserveScroll: true, onFinish: () => setSaving(false), onSuccess: () => handleClose() };
    if (editing === 'new') {
      router.post(companyProjectTeamsPath(project.id), payload, options);
    } else if (editing) {
      router.patch(companyProjectTeamPath(project.id, editing.id), payload, options);
    }
  };

  const handleDelete = (team: ProjectTeam) => {
    modals.openConfirmModal({
      title: 'Delete team',
      children: (
        <Text size="sm">
          Delete team <b>{team.name}</b>? Tasks assigned to it become unassigned. A team that a trigger runs as cannot
          be deleted until those triggers run as someone else.
        </Text>
      ),
      labels: { confirm: 'Delete', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => router.delete(companyProjectTeamPath(project.id, team.id), { preserveScroll: true }),
    });
  };

  const handleLeave = (team: ProjectTeam) => {
    modals.openConfirmModal({
      title: 'Leave team',
      children: (
        <Text size="sm">
          Leave team <b>{team.name}</b>? Its runs will no longer be handed to you.
        </Text>
      ),
      labels: { confirm: 'Leave', cancel: 'Cancel' },
      confirmProps: { color: 'red' },
      onConfirm: () => router.delete(leaveCompanyProjectTeamPath(project.id, team.id), { preserveScroll: true }),
    });
  };

  const addable = candidates
    .filter((c) => !form.memberIds.includes(c.id) && !c.excludedFromTeams)
    .map((c) => ({
      value: String(c.id),
      label: c.agentConnected ? c.name : `${c.name} — no agent connected`,
    }));

  return (
    <>
      <Head title={`Teams — ${project.name}`} />
      <Box>
        <PageHeader
          title="Teams"
          subtitle="A team is a group of project members that a task can be assigned to and a trigger can run as. Each run goes to one member, picked by the team's strategy, and runs on that member's own agent subscription."
          actions={
            canManage && (
              <Button leftSection={<IconPlus size={16} />} onClick={openNew}>
                New team
              </Button>
            )
          }
        />

        {teams.length === 0 ? (
          <Box
            style={{
              border: '1px solid var(--app-border-default)',
              borderRadius: 'var(--mantine-radius-md)',
              backgroundColor: 'var(--app-bg-paper)',
            }}
          >
            <EmptyState icon={<IconUsersGroup size={22} />} title="No teams yet" />
          </Box>
        ) : (
          <Box style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(320px, 1fr))', gap: 20 }}>
            {teams.map((team) => (
              <TeamCard
                key={team.id}
                team={team}
                currentUserId={currentUser?.id}
                canManage={canManage}
                onEdit={() => openEdit(team)}
                onLeave={() => handleLeave(team)}
              />
            ))}
          </Box>
        )}

        <ResourceDrawer
          opened={editing !== null}
          onClose={requestClose}
          title={editing === 'new' ? 'New team' : 'Edit team'}
          footer={
            <Stack gap="xs">
              <Button fullWidth onClick={handleSave} loading={saving} disabled={!form.name.trim()}>
                {editing === 'new' ? 'Create team' : 'Save team'}
              </Button>
              {editing && editing !== 'new' && (
                <Button
                  fullWidth
                  variant="subtle"
                  color="red"
                  leftSection={<IconTrash size={14} />}
                  onClick={() => handleDelete(editing)}
                >
                  Delete team
                </Button>
              )}
            </Stack>
          }
        >
          <Stack gap="md">
            <TextInput
              label="Name"
              value={form.name}
              onChange={(e) => {
                const name = e.currentTarget.value;
                setForm((f) => ({ ...f, name }));
              }}
              required
            />
            <Select
              label="Strategy"
              description="How a run picks the member it goes to"
              data={STRATEGY_OPTIONS.map((o) => ({ value: o.value, label: `${o.label} — ${o.description}` }))}
              value={form.strategy}
              onChange={(value) => value && setForm((f) => ({ ...f, strategy: value as Strategy }))}
              allowDeselect={false}
            />
            <Box>
              <Text size="sm" fw={500} mb={4}>
                Members
              </Text>
              <Text size="xs" c="dimmed" mb="sm">
                In the team&apos;s order. Priority goes down this list; round robin goes around it.
              </Text>
              {form.memberIds.length === 0 ? (
                <Text size="sm" c="dimmed" mb="sm">
                  No members yet
                </Text>
              ) : (
                <Stack gap={4} mb="sm" aria-label="Team members" role="list">
                  {form.memberIds.map((id, index) => {
                    const name = memberName(id);
                    const candidate = candidateById.get(id);
                    return (
                      <Group key={id} justify="space-between" wrap="nowrap" role="listitem">
                        <Box style={{ minWidth: 0 }}>
                          <Text size="sm">
                            {index + 1}. {name}
                          </Text>
                          {candidate && !candidate.agentConnected && (
                            <Text size="xs" c="dimmed">
                              No agent connected — runs skip them until they connect one
                            </Text>
                          )}
                        </Box>
                        <Group gap={2} wrap="nowrap">
                          <ActionIcon
                            aria-label={`Move ${name} up`}
                            variant="subtle"
                            size="sm"
                            disabled={index === 0}
                            onClick={() => moveMember(index, -1)}
                          >
                            <IconArrowUp size={14} />
                          </ActionIcon>
                          <ActionIcon
                            aria-label={`Move ${name} down`}
                            variant="subtle"
                            size="sm"
                            disabled={index === form.memberIds.length - 1}
                            onClick={() => moveMember(index, 1)}
                          >
                            <IconArrowDown size={14} />
                          </ActionIcon>
                          <ActionIcon
                            aria-label={`Remove ${name}`}
                            variant="subtle"
                            size="sm"
                            color="red"
                            onClick={() => removeMember(id)}
                          >
                            <IconX size={14} />
                          </ActionIcon>
                        </Group>
                      </Group>
                    );
                  })}
                </Stack>
              )}
              <Select
                label="Add member"
                placeholder="Choose a project member…"
                data={addable}
                value={addingId}
                onChange={addMember}
                searchable
                nothingFoundMessage="No members to add"
              />
            </Box>
          </Stack>
        </ResourceDrawer>
      </Box>
    </>
  );
};

setPageLayout(TeamsPage, persistentProjectLayout);

export default TeamsPage;
