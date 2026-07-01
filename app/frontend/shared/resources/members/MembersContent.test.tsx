import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import { MembersContent, type MemberUser } from './MembersContent';

const makeUser = (over: Partial<MemberUser> = {}): MemberUser => ({
  id: 1,
  email: 'ada@example.com',
  name: 'Ada Lovelace',
  role: 'employee',
  state: 'active',
  position: null,
  invitedAt: null,
  createdAt: '2024-01-01T00:00:00Z',
  invitedBy: null,
  ...over,
});

const baseProps = (users: MemberUser[]) => ({
  users,
  basePath: '/company/members',
  title: 'Members',
});

describe('MembersContent', () => {
  it('renders the title and a row for each seeded user', () => {
    renderPage(
      <MembersContent
        {...baseProps([
          makeUser({ id: 1, name: 'Ada Lovelace', email: 'ada@example.com' }),
          makeUser({ id: 2, name: 'Grace Hopper', email: 'grace@example.com', role: 'admin' }),
        ])}
      />,
    );

    expect(screen.getByRole('heading', { name: 'Members' })).toBeInTheDocument();
    expect(screen.getByText('Ada Lovelace')).toBeInTheDocument();
    expect(screen.getByText('grace@example.com')).toBeInTheDocument();
    expect(screen.getByText('2 members')).toBeInTheDocument();
  });

  it('shows the empty state when there are no members', () => {
    renderPage(<MembersContent {...baseProps([])} />);

    expect(screen.getByText('No members found')).toBeInTheDocument();
    expect(screen.getByText('0 members')).toBeInTheDocument();
  });

  it('search narrows the list to matching members', async () => {
    renderPage(
      <MembersContent
        {...baseProps([
          makeUser({ id: 1, name: 'Ada Lovelace', email: 'ada@example.com' }),
          makeUser({ id: 2, name: 'Grace Hopper', email: 'grace@example.com' }),
        ])}
      />,
    );

    await userEvent.type(screen.getByPlaceholderText(/search by name or email/i), 'grace');

    expect(screen.getByText('Grace Hopper')).toBeInTheDocument();
    expect(screen.queryByText('Ada Lovelace')).not.toBeInTheDocument();
    expect(screen.getByText('1 member')).toBeInTheDocument();
  });

  it('the Invite Member button opens the invite modal', async () => {
    renderPage(<MembersContent {...baseProps([makeUser()])} />);

    await userEvent.click(screen.getByRole('button', { name: /invite member/i }));

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText('Invite Member')).toBeInTheDocument();
    expect(within(dialog).getByRole('button', { name: /send invitation/i })).toBeInTheDocument();
  });

  it('confirming Remove in the row menu fires router.delete', async () => {
    vi.spyOn(window, 'confirm').mockReturnValue(true);
    // Two active admins so neither is the "last admin" (which would disable Remove).
    renderPage(
      <MembersContent
        {...baseProps([
          makeUser({ id: 7, name: 'Ada Lovelace', role: 'admin', state: 'active' }),
          makeUser({ id: 8, name: 'Grace Hopper', role: 'admin', state: 'active' }),
        ])}
      />,
    );

    // Open the action menu of Ada's row specifically (each row has one ActionIcon button).
    const adaRow = screen.getByText('Ada Lovelace').closest('tr') as HTMLElement;
    await userEvent.click(within(adaRow).getByRole('button'));

    // The menu actions render in a dropdown; click the Remove item once visible.
    const remove = await screen.findByRole('menuitem', { name: /remove/i });
    await userEvent.click(remove);

    await waitFor(() =>
      expect(router.delete).toHaveBeenCalledWith(
        '/company/members/7',
        expect.objectContaining({ preserveScroll: true }),
      ),
    );
  });

  it('the "Make Admin" menu action fires router.patch with the new role', async () => {
    renderPage(<MembersContent {...baseProps([makeUser({ id: 9, name: 'Ada Lovelace', role: 'employee' })])} />);

    // Open the row's action menu (the dots icon button).
    const row = screen.getByText('Ada Lovelace').closest('tr') as HTMLElement;
    await userEvent.click(within(row).getByRole('button'));

    const makeAdmin = await screen.findByRole('menuitem', { name: /make admin/i });
    await userEvent.click(makeAdmin);

    await waitFor(() =>
      expect(router.patch).toHaveBeenCalledWith(
        '/company/members/9',
        { user: { role: 'admin' } },
        expect.objectContaining({ preserveScroll: true }),
      ),
    );
  });

  it('renders a non-empty badge for a viewer member', () => {
    renderPage(<MembersContent {...baseProps([makeUser({ id: 5, name: 'Vic Viewer', role: 'viewer' })])} />);

    const row = screen.getByText('Vic Viewer').closest('tr') as HTMLElement;
    expect(within(row).getByText('Viewer')).toBeInTheDocument();
  });
});
