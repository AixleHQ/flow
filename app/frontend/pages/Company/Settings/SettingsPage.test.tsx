import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { renderAuthedPage, screen, userEvent, waitFor } from 'test/renderPage';

import SettingsPage from './SettingsPage';

const company = {
  name: 'Acme Robotics',
  displayName: null,
  emailDomain: 'acme-robotics.example',
  logoUrl: null,
  primaryColor: '#4785FF',
  secondaryColor: '#bb9af7',
  autoAcceptUsers: false,
};

const capacity = {
  maxSessions: 20,
  available: 14,
  reserved: 6,
  allocations: [{ name: 'Gateway', maxSessions: 6 }],
  projectDefault: 4,
  queueEnabled: true,
  canManage: true,
};

describe('Company settings page', () => {
  it('reports the capacity and how the projects spent it', () => {
    renderAuthedPage(<SettingsPage />, { props: { company, capacity, canManage: true } });

    expect(screen.getByText(/6 of 20 is reserved by projects, leaving 14/)).toBeInTheDocument();
    expect(screen.getByText(/Reserved: Gateway 6/)).toBeInTheDocument();
  });

  it('lets a self-hosted admin change the limit', async () => {
    const patch = vi.spyOn(router, 'patch').mockImplementation(() => undefined);
    renderAuthedPage(<SettingsPage />, { props: { company, capacity, canManage: true } });

    await userEvent.clear(screen.getByLabelText(/Concurrent sessions/));
    await userEvent.type(screen.getByLabelText(/Concurrent sessions/), '30');
    await userEvent.click(screen.getByRole('button', { name: 'Save Changes' }));

    await waitFor(() => expect(patch).toHaveBeenCalled());
    expect(patch.mock.calls[0][1]).toMatchObject({ capacity: '30' });
  });

  // The hosted product invoices for this number, so it is shown and not offered.
  it('shows the limit read-only when it is not this admin to move', () => {
    renderAuthedPage(<SettingsPage />, {
      props: { company, capacity: { ...capacity, canManage: false }, canManage: true },
    });

    expect(screen.queryByLabelText(/Concurrent sessions/)).not.toBeInTheDocument();
    expect(screen.getByText('20')).toBeInTheDocument();
    expect(screen.getByText(/contact us to change this/)).toBeInTheDocument();
  });

  // Omitting the key is what tells the server no limit was submitted at all —
  // sending an empty one would clear it.
  it('never submits a capacity it may not set', async () => {
    const patch = vi.spyOn(router, 'patch').mockImplementation(() => undefined);
    renderAuthedPage(<SettingsPage />, {
      props: { company, capacity: { ...capacity, canManage: false }, canManage: true },
    });

    await userEvent.type(screen.getByLabelText(/Display name/), 'Acme');
    await userEvent.click(screen.getByRole('button', { name: 'Save Changes' }));

    await waitFor(() => expect(patch).toHaveBeenCalled());
    expect(patch.mock.calls[0][1]).not.toHaveProperty('capacity');
  });

  it('says nothing is held back while the queue is off', () => {
    renderAuthedPage(<SettingsPage />, {
      props: { company, capacity: { ...capacity, queueEnabled: false }, canManage: true },
    });

    expect(screen.getByText(/nothing is being held back yet/)).toBeInTheDocument();
  });

  it('hides the save button from someone who may not write', () => {
    renderAuthedPage(<SettingsPage />, {
      props: { company, capacity: { ...capacity, canManage: false }, canManage: false },
    });

    expect(screen.queryByRole('button', { name: 'Save Changes' })).not.toBeInTheDocument();
  });
});
