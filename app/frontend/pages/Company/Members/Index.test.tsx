import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

import type { MemberUser } from 'shared/resources/members/MembersContent';

import MembersIndex from './Index';

const member = (overrides: Partial<MemberUser> = {}): MemberUser => ({
  id: 1,
  email: 'dana@example.com',
  name: 'Dana Member',
  role: 'employee',
  state: 'active',
  position: null,
  invitedAt: null,
  createdAt: '2026-01-01T00:00:00Z',
  invitedBy: null,
  ...overrides,
});

describe('Company/Members/Index', () => {
  it('renders the heading and lists seeded members', () => {
    renderAuthedPage(
      <MembersIndex
        users={[
          member({ id: 1, name: 'Dana Member', email: 'dana@example.com' }),
          member({ id: 2, name: 'Glenn Globex', email: 'glenn@example.com' }),
        ]}
      />,
    );

    expect(screen.getByRole('heading', { name: 'Company Members' })).toBeInTheDocument();
    expect(screen.getByText('Dana Member')).toBeInTheDocument();
    expect(screen.getByText('Glenn Globex')).toBeInTheDocument();
    expect(screen.getByText('2 members')).toBeInTheDocument();
  });

  it('filters members by the search query', async () => {
    renderAuthedPage(
      <MembersIndex
        users={[
          member({ id: 1, name: 'Dana Member', email: 'dana@example.com' }),
          member({ id: 2, name: 'Glenn Globex', email: 'glenn@example.com' }),
        ]}
      />,
    );

    await userEvent.type(screen.getByPlaceholderText('Search by name or email...'), 'glenn');

    expect(screen.queryByText('Dana Member')).not.toBeInTheDocument();
    expect(screen.getByText('Glenn Globex')).toBeInTheDocument();
  });

  it('shows the empty state when the search matches no member', async () => {
    renderAuthedPage(<MembersIndex users={[member({ name: 'Dana Member' })]} />);

    await userEvent.type(screen.getByPlaceholderText('Search by name or email...'), 'zzz');

    expect(screen.getByText('No members found')).toBeInTheDocument();
    expect(screen.queryByText('Dana Member')).not.toBeInTheDocument();
  });

  it('promotes an employee to admin via the row menu, firing router.patch', async () => {
    renderAuthedPage(
      // Include an existing admin so the employee row is never "last admin" gated.
      <MembersIndex
        users={[
          member({ id: 5, name: 'Eve Employee', email: 'eve@example.com', role: 'employee' }),
          member({ id: 9, name: 'Ada Admin', email: 'ada@example.com', role: 'admin' }),
        ]}
      />,
    );

    const employeeRow = screen.getByText('Eve Employee').closest('tr') as HTMLElement;
    await userEvent.click(within(employeeRow).getByRole('button'));

    await userEvent.click(await screen.findByRole('menuitem', { name: 'Make Admin' }));

    expect(router.patch).toHaveBeenCalledWith(
      '/company/members/5',
      { user: { role: 'admin' } },
      { preserveScroll: true },
    );
  });
});
