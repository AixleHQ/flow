import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent } from 'test/renderPage';

import YoutrackConnect from './YoutrackConnect';

const PROJECTS = [
  { id: 12, name: 'Support', companyName: 'Acme' },
  { id: 14, name: 'Billing', companyName: 'Acme' },
];

describe('YouTrack connect page', () => {
  beforeEach(() => vi.mocked(router.post).mockClear());

  it('approves the typed code for the chosen project once both are given', async () => {
    const user = userEvent.setup();
    renderPage(<YoutrackConnect />, { props: { projects: PROJECTS, flash: {} } });

    const approve = screen.getByRole('button', { name: 'Approve' });
    expect(approve).toBeDisabled();
    await user.type(screen.getByLabelText('Code'), ' abcd-2345 ');
    expect(approve).toBeDisabled();
    await user.click(screen.getByRole('combobox', { name: 'Aixle project' }));
    await user.click(await screen.findByRole('option', { name: 'Billing' }));
    await user.click(approve);

    expect(router.post).toHaveBeenCalledWith(
      '/integrations/youtrack/connect',
      { code: 'abcd-2345', project_id: 14 },
      expect.anything(),
    );
  });

  it('names the company beside each project when the user is in several', async () => {
    const user = userEvent.setup();
    renderPage(<YoutrackConnect />, {
      props: { projects: [...PROJECTS, { id: 20, name: 'Support', companyName: 'Globex' }], flash: {} },
    });

    await user.click(screen.getByRole('combobox', { name: 'Aixle project' }));

    expect(await screen.findByRole('option', { name: 'Support · Acme' })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'Support · Globex' })).toBeInTheDocument();
  });

  it('sends the user back to YouTrack once the code is approved', () => {
    const notice = 'Approved: https://acme.youtrack.cloud connects to Support. Go back to YouTrack to finish.';
    renderPage(<YoutrackConnect />, { props: { projects: PROJECTS, flash: { notice } } });

    expect(screen.getByText(notice)).toBeInTheDocument();
    expect(screen.getByText(/Return to the YouTrack tab/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Approve' })).not.toBeInTheDocument();
  });

  it('shows why the code was refused and keeps the form', () => {
    const alert = 'That code is unknown or has expired — start again in YouTrack';
    renderPage(<YoutrackConnect />, { props: { projects: PROJECTS, flash: { alert } } });

    expect(screen.getByText(alert)).toBeInTheDocument();
    expect(screen.getByLabelText('Code')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Approve' })).toBeInTheDocument();
  });
});
