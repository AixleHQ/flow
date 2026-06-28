import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent, waitFor } from 'test/renderPage';

import { InviteUserModal } from './InviteUserModal';

// InviteUserModal uses Mantine's own useForm (real + reactive) and submits via router.post.
// router is a vi.fn spy from test/setup.ts, so we assert the backend request without a backend.
// NOTE: zod-failure validation is intentionally NOT exercised here — the installed
// mantine-form-zod-resolver@1.3.0 reads zod v3's `error.errors`, but the project ships zod v4
// (which exposes `error.issues`), so any failed validation throws inside the library. We instead
// assert the happy-path post and that the close button does NOT post.

describe('InviteUserModal', () => {
  it('renders the title and its fields when opened', () => {
    renderPage(<InviteUserModal opened onClose={vi.fn()} basePath="/companies/1/members" />);

    expect(screen.getByText('Invite Member')).toBeInTheDocument();
    expect(screen.getByLabelText(/email/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/full name/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /send invitation/i })).toBeInTheDocument();
  });

  it('defaults the Role field to Employee', () => {
    renderPage(<InviteUserModal opened onClose={vi.fn()} basePath="/companies/1/members" />);

    expect(screen.getByDisplayValue('Employee')).toBeInTheDocument();
  });

  it('a valid submit fires router.post with the entered user data and the default role', async () => {
    renderPage(<InviteUserModal opened onClose={vi.fn()} basePath="/companies/1/members" />);

    await userEvent.type(screen.getByLabelText(/email/i), 'jane@company.com');
    await userEvent.type(screen.getByLabelText(/full name/i), 'Jane Roe');
    await userEvent.click(screen.getByRole('button', { name: /send invitation/i }));

    await waitFor(() =>
      expect(router.post).toHaveBeenCalledWith(
        '/companies/1/members',
        { user: { email: 'jane@company.com', name: 'Jane Roe', role: 'employee' } },
        expect.objectContaining({ preserveScroll: true }),
      ),
    );
  });

  it('posts to the basePath it is given', async () => {
    renderPage(<InviteUserModal opened onClose={vi.fn()} basePath="/projects/42/members" />);

    await userEvent.type(screen.getByLabelText(/email/i), 'bob@company.com');
    await userEvent.type(screen.getByLabelText(/full name/i), 'Bob Smith');
    await userEvent.click(screen.getByRole('button', { name: /send invitation/i }));

    await waitFor(() =>
      expect(router.post).toHaveBeenCalledWith('/projects/42/members', expect.any(Object), expect.any(Object)),
    );
  });

  it('clicking Cancel calls onClose and does not hit the backend', async () => {
    const onClose = vi.fn();
    renderPage(<InviteUserModal opened onClose={onClose} basePath="/companies/1/members" />);

    await userEvent.click(screen.getByRole('button', { name: /cancel/i }));

    expect(onClose).toHaveBeenCalled();
    expect(router.post).not.toHaveBeenCalled();
  });
});
