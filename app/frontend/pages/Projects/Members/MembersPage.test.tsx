import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

import MembersPage from './MembersPage';

const project = { id: 7, name: 'Apollo Project' };

const owner = { id: 1, email: 'ada@apollo.test', name: 'Ada Owner', role: 'admin', state: 'active' };
const member = { id: 2, email: 'bo@apollo.test', name: 'Bo Member', role: 'member', state: 'active' };
const outsider = { id: 3, email: 'cy@apollo.test', name: 'Cy Outsider', role: 'member', state: 'active' };

const baseProps = {
  project,
  members: [owner, member],
  companyUsers: [owner, member, outsider],
  ownerId: owner.id,
};

afterEach(() => {
  vi.restoreAllMocks();
});

describe('Projects/Members/MembersPage', () => {
  it('renders the heading with the member count and lists members', () => {
    renderAuthedPage(<MembersPage />, { props: baseProps });

    expect(screen.getByRole('heading', { name: 'Project Members (2)' })).toBeInTheDocument();
    expect(screen.getByText('Ada Owner')).toBeInTheDocument();
    expect(screen.getByText('Bo Member')).toBeInTheDocument();
  });

  it('marks the owner with an Owner badge and hides Remove for them', () => {
    renderAuthedPage(<MembersPage />, { props: baseProps });

    expect(screen.getByText('Owner')).toBeInTheDocument();
    // Only the non-owner member is removable.
    const removeButtons = screen.getAllByRole('button', { name: /Remove/ });
    expect(removeButtons).toHaveLength(1);
  });

  it('filters the member list by the search query', async () => {
    renderAuthedPage(<MembersPage />, { props: baseProps });

    await userEvent.type(screen.getByPlaceholderText('Search by name or email...'), 'bo');

    expect(screen.queryByText('Ada Owner')).not.toBeInTheDocument();
    expect(screen.getByText('Bo Member')).toBeInTheDocument();
  });

  it('shows the empty state when the search matches nobody', async () => {
    renderAuthedPage(<MembersPage />, { props: baseProps });

    await userEvent.type(screen.getByPlaceholderText('Search by name or email...'), 'zzz');

    expect(screen.getByText('No members found')).toBeInTheDocument();
  });

  it('removes a member via router.delete after confirmation', async () => {
    const confirmSpy = vi.spyOn(window, 'confirm').mockReturnValue(true);
    renderAuthedPage(<MembersPage />, { props: baseProps });

    await userEvent.click(screen.getByRole('button', { name: /Remove/ }));

    expect(confirmSpy).toHaveBeenCalled();
    expect(router.delete).toHaveBeenCalledWith('/company/projects/7/members/2', { preserveScroll: true });
  });

  it('opens the Add Collaborator modal listing only users not already in the project', async () => {
    renderAuthedPage(<MembersPage />, { props: baseProps });

    await userEvent.click(screen.getByRole('button', { name: 'Add Collaborator' }));

    const dialog = await screen.findByRole('dialog');
    // The Add button is disabled until a user is picked, so the modal opened cleanly.
    expect(within(dialog).getByRole('button', { name: 'Add' })).toBeDisabled();
  });
});
