import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { afterEach, describe, expect, it, vi } from 'vitest';

import { renderAuthedPage, screen, userEvent, waitFor, within } from 'test/renderPage';

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
    renderAuthedPage(<MembersPage />, { props: baseProps });

    await userEvent.click(screen.getByRole('button', { name: /Remove/ }));

    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Remove' }));

    await waitFor(() =>
      expect(router.delete).toHaveBeenCalledWith('/company/projects/7/members/2', { preserveScroll: true }),
    );
  });

  it('opens the Add Collaborator modal listing only users not already in the project', async () => {
    renderAuthedPage(<MembersPage />, { props: baseProps });

    await userEvent.click(screen.getByRole('button', { name: 'Add Collaborator' }));

    const dialog = await screen.findByRole('dialog');
    // The Add button is disabled until a user is picked, so the modal opened cleanly.
    expect(within(dialog).getByRole('button', { name: 'Add' })).toBeDisabled();
  });

  it('does not delete a member when the confirmation is declined', async () => {
    renderAuthedPage(<MembersPage />, { props: baseProps });

    await userEvent.click(screen.getByRole('button', { name: /Remove/ }));

    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Cancel' }));

    expect(router.delete).not.toHaveBeenCalled();
  });

  it('filters members by an email substring, not just the name', async () => {
    renderAuthedPage(<MembersPage />, { props: baseProps });

    // "ada@" appears only in the owner's email, never in any display name, so a match here can
    // only come from the email branch of the filter predicate.
    await userEvent.type(screen.getByPlaceholderText('Search by name or email...'), 'ada@');

    expect(screen.getByText('Ada Owner')).toBeInTheDocument();
    expect(screen.queryByText('Bo Member')).not.toBeInTheDocument();
  });

  it('offers only company users not already in the project in the add picker', async () => {
    renderAuthedPage(<MembersPage />, { props: baseProps });

    await userEvent.click(screen.getByRole('button', { name: 'Add Collaborator' }));
    await userEvent.click(await screen.findByRole('combobox', { name: /select user/i }));

    expect(await screen.findByRole('option', { name: 'Cy Outsider (cy@apollo.test)' })).toBeInTheDocument();
    // The owner and existing member are already collaborators, so they are excluded from the options.
    expect(screen.queryByRole('option', { name: /Ada Owner/ })).not.toBeInTheDocument();
    expect(screen.queryByRole('option', { name: /Bo Member/ })).not.toBeInTheDocument();
  });

  it('posts the chosen collaborator once a user is selected', async () => {
    renderAuthedPage(<MembersPage />, { props: baseProps });

    await userEvent.click(screen.getByRole('button', { name: 'Add Collaborator' }));
    const dialog = await screen.findByRole('dialog');

    await userEvent.click(within(dialog).getByRole('combobox', { name: /select user/i }));
    await userEvent.click(await screen.findByRole('option', { name: 'Cy Outsider (cy@apollo.test)' }));

    // Picking a user flips the Add button from disabled to enabled.
    const addButton = within(dialog).getByRole('button', { name: 'Add' });
    expect(addButton).toBeEnabled();

    await userEvent.click(addButton);

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/7/members',
      { collaborator: { userId: 3 } },
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('closes the add modal after a successful add', async () => {
    // Drive the success path: the mocked router invokes the onSuccess/onFinish callbacks the
    // component passes, which close the modal and reset the picker. mockImplementationOnce reverts
    // after this single call, so the pinned behavior never leaks into a later test.
    vi.mocked(router.post).mockImplementationOnce((_url, _data, options) => {
      const opts = options as { onSuccess?: () => void; onFinish?: () => void } | undefined;
      opts?.onSuccess?.();
      opts?.onFinish?.();
    });
    renderAuthedPage(<MembersPage />, { props: baseProps });

    await userEvent.click(screen.getByRole('button', { name: 'Add Collaborator' }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('combobox', { name: /select user/i }));
    await userEvent.click(await screen.findByRole('option', { name: 'Cy Outsider (cy@apollo.test)' }));
    await userEvent.click(within(dialog).getByRole('button', { name: 'Add' }));

    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
  });

  it('closes the add modal without posting when Cancel is clicked', async () => {
    renderAuthedPage(<MembersPage />, { props: baseProps });

    await userEvent.click(screen.getByRole('button', { name: 'Add Collaborator' }));
    const dialog = await screen.findByRole('dialog');

    await userEvent.click(within(dialog).getByRole('button', { name: 'Cancel' }));

    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    expect(router.post).not.toHaveBeenCalled();
  });

  it('falls back to the email for the label and avatar initials when a member has no name', () => {
    const noName = { id: 4, email: 'dee@apollo.test', name: '', role: 'member', state: 'active' };
    renderAuthedPage(<MembersPage />, {
      props: {
        ...baseProps,
        members: [owner, member, noName],
        companyUsers: [owner, member, outsider, noName],
      },
    });

    expect(screen.getByRole('heading', { name: 'Project Members (3)' })).toBeInTheDocument();
    // With no name the avatar initials come from the email's first letter ("D"), and the email
    // itself is used as the primary label (so it renders both as the label and the dimmed subtext).
    expect(screen.getByText('D')).toBeInTheDocument();
    expect(screen.getAllByText('dee@apollo.test').length).toBeGreaterThan(0);
  });
});
