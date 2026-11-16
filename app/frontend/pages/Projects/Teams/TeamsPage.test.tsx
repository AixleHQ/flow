import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { buildProject } from 'test/factories/project';
import { buildProjectTeam, buildTeamMember } from 'test/factories/projectTeam';
import { buildSharedUser } from 'test/factories/sharedProps';
import { renderAuthedPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import TeamsPage, { type TeamCandidate } from './TeamsPage';

const project = buildProject({ id: 7, name: 'Apollo Project' });

const anna = buildTeamMember({ id: 2, name: 'Anna', email: 'anna@apollo.test' });
const pavel = buildTeamMember({
  id: 3,
  name: 'Pavel',
  email: 'pavel@apollo.test',
  status: {
    state: 'on_hold',
    until: '2026-12-01T12:00:00Z',
    detail: 'Kiro CLI quota exhausted until 2026-12-01 12:00 UTC',
  },
  runtimes: [{ agentType: 'kiro_cli', label: 'Kiro CLI', quotaExhaustedUntil: '2026-12-01T12:00:00Z' }],
});
const olga = buildTeamMember({
  id: 4,
  name: 'Olga',
  email: 'olga@apollo.test',
  status: { state: 'unavailable', until: null, detail: 'has no agent connected in this company' },
  runtimes: [],
});

const candidates: TeamCandidate[] = [
  { id: 2, name: 'Anna', agentConnected: true, excludedFromTeams: false },
  { id: 3, name: 'Pavel', agentConnected: true, excludedFromTeams: false },
  { id: 4, name: 'Olga', agentConnected: false, excludedFromTeams: false },
  { id: 5, name: 'Ivan', agentConnected: true, excludedFromTeams: true },
];

const planner = buildProjectTeam({
  id: 11,
  name: 'Planner',
  members: [anna, pavel, olga],
  nextMemberId: anna.id,
  triggers: [{ id: 5, name: 'Every weekday', workflowName: 'Nightly planning' }],
  triggerCount: 1,
  taskCount: 2,
});

const renderTeams = (props: Record<string, unknown> = {}) =>
  renderAuthedPage(<TeamsPage />, {
    props: { project, teams: [planner], candidates, canManage: true, ...props },
  });

afterEach(() => {
  vi.restoreAllMocks();
});

describe('Projects/Teams/TeamsPage', () => {
  it('shows each team as a card: strategy, members in order with whether they can take a run, who is next, and what uses it', () => {
    renderTeams();

    expect(screen.getByRole('heading', { name: 'Teams', level: 1 })).toBeInTheDocument();
    const card = screen.getByRole('region', { name: 'Planner' });
    expect(within(card).getByText('Priority')).toBeInTheDocument();
    const members = within(within(card).getByRole('list', { name: 'Planner members' })).getAllByRole('listitem');
    expect(members.map((m) => m.textContent)).toEqual([
      expect.stringMatching(/^1.*Anna.*Next.*Ready$/),
      expect.stringMatching(/^2.*Pavel.*On hold until/),
      expect.stringMatching(/^3.*Olga.*Can't take runs$/),
    ]);
    expect(within(card).getByText('Nightly planning · 2 cards')).toBeInTheDocument();
  });

  it('says why a member cannot take a run when their status is hovered', async () => {
    renderTeams();

    await userEvent.hover(screen.getByText(/On hold until/));

    expect(await screen.findByText('Kiro CLI quota exhausted until 2026-12-01 12:00 UTC')).toBeInTheDocument();
  });

  it('marks a member whose login expired, and says how to fix it on hover', async () => {
    const maria = buildTeamMember({
      id: 6,
      name: 'Maria',
      status: {
        state: 'signed_out',
        until: null,
        detail: 'Kiro CLI login expired — sign in again in Profile settings',
      },
    });
    renderTeams({ teams: [buildProjectTeam({ id: 12, name: 'Night shift', members: [maria], nextMemberId: null })] });

    await userEvent.hover(screen.getByText('Login expired'));

    expect(await screen.findByText('Kiro CLI login expired — sign in again in Profile settings')).toBeInTheDocument();
  });

  it('shows the empty state when the project has no teams', () => {
    renderTeams({ teams: [] });

    expect(screen.getByText('No teams yet')).toBeInTheDocument();
  });

  it('hides creating, editing and deleting from someone who cannot manage teams', () => {
    renderTeams({ canManage: false });

    expect(screen.queryByRole('button', { name: 'New team' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Edit Planner' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Delete Planner' })).not.toBeInTheDocument();
  });

  it('creates a team with a strategy and an ordered member list', async () => {
    renderTeams({ teams: [] });

    await userEvent.click(screen.getByRole('button', { name: 'New team' }));
    const drawer = await screen.findByRole('dialog');
    await userEvent.type(within(drawer).getByRole('textbox', { name: /Name/ }), 'Night shift');

    await userEvent.click(within(drawer).getByRole('combobox', { name: /Strategy/ }));
    await userEvent.click(await screen.findByRole('option', { name: /Round robin/ }));

    await userEvent.click(within(drawer).getByRole('combobox', { name: 'Add member' }));
    expect(screen.queryByRole('option', { name: /Ivan/ })).not.toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'Olga — no agent connected' })).toBeInTheDocument();
    await userEvent.click(screen.getByRole('option', { name: 'Pavel' }));
    await userEvent.click(within(drawer).getByRole('combobox', { name: 'Add member' }));
    await userEvent.click(await screen.findByRole('option', { name: 'Anna' }));

    await userEvent.click(within(drawer).getByRole('button', { name: 'Move Anna up' }));
    await userEvent.click(within(drawer).getByRole('button', { name: 'Create team' }));

    await waitFor(() =>
      expect(router.post).toHaveBeenCalledWith(
        '/company/projects/7/teams',
        { team: { name: 'Night shift', strategy: 'round_robin', memberIds: [2, 3] } },
        expect.objectContaining({ preserveScroll: true }),
      ),
    );
  });

  it('saves an edited team with a member removed', async () => {
    renderTeams();

    await userEvent.click(screen.getByRole('button', { name: 'Edit Planner' }));
    const drawer = await screen.findByRole('dialog');
    const members = within(drawer).getByRole('list', { name: 'Team members' });
    expect(
      within(members)
        .getAllByRole('listitem')
        .map((item) => item.textContent),
    ).toEqual([expect.stringContaining('Anna'), expect.stringContaining('Pavel'), expect.stringContaining('Olga')]);

    await userEvent.click(within(drawer).getByRole('button', { name: 'Remove Anna' }));
    await userEvent.click(within(drawer).getByRole('button', { name: 'Save team' }));

    await waitFor(() =>
      expect(router.patch).toHaveBeenCalledWith(
        '/company/projects/7/teams/11',
        { team: { name: 'Planner', strategy: 'priority', memberIds: [3, 4] } },
        expect.objectContaining({ preserveScroll: true }),
      ),
    );
  });

  it('deletes a team from its editor, after confirmation', async () => {
    renderTeams();

    await userEvent.click(screen.getByRole('button', { name: 'Edit Planner' }));
    const drawer = await screen.findByRole('dialog');
    await userEvent.click(within(drawer).getByRole('button', { name: 'Delete team' }));
    const confirm = await screen.findByRole('dialog', { name: 'Delete team' });
    await userEvent.click(within(confirm).getByRole('button', { name: 'Delete' }));

    await waitFor(() =>
      expect(router.delete).toHaveBeenCalledWith('/company/projects/7/teams/11', { preserveScroll: true }),
    );
  });

  it('lets a member of a team leave it', async () => {
    renderTeams({ canManage: false, currentUser: buildSharedUser({ id: anna.id }) });

    await userEvent.click(screen.getByRole('button', { name: 'Leave Planner' }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Leave' }));

    await waitFor(() =>
      expect(router.delete).toHaveBeenCalledWith('/company/projects/7/teams/11/leave', { preserveScroll: true }),
    );
  });

  it('offers no Leave to someone outside the team', () => {
    renderTeams();

    expect(screen.queryByRole('button', { name: 'Leave Planner' })).not.toBeInTheDocument();
  });
});
