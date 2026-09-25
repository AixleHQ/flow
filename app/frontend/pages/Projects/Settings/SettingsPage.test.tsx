import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { notifications } from '@mantine/notifications';
import { describe, expect, it, vi } from 'vitest';

import { act, renderAuthedPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import SettingsPage from './SettingsPage';

const project = {
  id: 7,
  name: 'Gateway Service',
  description: 'Edge routing layer',
  slug: 'gateway-service',
  state: 'active',
  preferredArtifactsLanguage: 'en',
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-02T00:00:00Z',
  ownerName: 'Dana Owner',
  ownerEmail: 'dana@example.com',
  canDelete: true,
};

const concurrency = {
  maxSessions: null,
  default: 4,
  companyLimit: null,
  available: null,
  allocations: [],
  canManage: true,
};

describe('Projects/Settings/SettingsPage', () => {
  it('renders the page title and section headings', () => {
    renderAuthedPage(<SettingsPage />, { props: { project, concurrency } });

    expect(screen.getByText('Project Settings')).toBeInTheDocument();
    expect(screen.getByText('General')).toBeInTheDocument();
    expect(screen.getByText('Details')).toBeInTheDocument();
    expect(screen.getByText('Danger Zone')).toBeInTheDocument();
  });

  it('renders the Details card with status, slug, owner, and created date', () => {
    renderAuthedPage(<SettingsPage />, { props: { project, concurrency } });

    expect(screen.getByText('Active')).toBeInTheDocument();
    expect(screen.getByText('gateway-service')).toBeInTheDocument();
    expect(screen.getByText('Dana Owner')).toBeInTheDocument();
    expect(screen.getByText('dana@example.com')).toBeInTheDocument();
    expect(screen.getByText('January 1, 2026')).toBeInTheDocument();
  });

  it('renders the existing description and selected language in the General form', () => {
    renderAuthedPage(<SettingsPage />, { props: { project, concurrency } });

    expect(screen.getByLabelText('Project Name')).toHaveValue('Gateway Service');
    expect(screen.getByLabelText('Description')).toHaveValue('Edge routing layer');
    expect(screen.getByDisplayValue('English')).toBeInTheDocument();
  });

  it('disables Save until the form is edited, then submits a patch with the trimmed values', async () => {
    renderAuthedPage(<SettingsPage />, { props: { project, concurrency } });

    const save = screen.getByRole('button', { name: 'Save Changes' });
    expect(save).toBeDisabled();

    const nameInput = screen.getByLabelText('Project Name');
    await userEvent.clear(nameInput);
    await userEvent.type(nameInput, 'Renamed Gateway');

    expect(save).toBeEnabled();
    await userEvent.click(save);

    expect(router.patch).toHaveBeenCalledWith(
      '/company/projects/7/settings',
      expect.objectContaining({
        project: expect.objectContaining({
          name: 'Renamed Gateway',
          preferredArtifactsLanguage: 'en',
        }),
      }),
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('keeps Save disabled when the name is cleared to whitespace only', async () => {
    renderAuthedPage(<SettingsPage />, { props: { project, concurrency } });

    const nameInput = screen.getByLabelText('Project Name');
    await userEvent.clear(nameInput);
    await userEvent.type(nameInput, '   ');

    expect(screen.getByRole('button', { name: 'Save Changes' })).toBeDisabled();
    expect(router.patch).not.toHaveBeenCalled();
  });

  it('submits the chosen artifacts language after picking a new option', async () => {
    renderAuthedPage(<SettingsPage />, { props: { project, concurrency } });

    await userEvent.click(screen.getByRole('combobox'));
    await userEvent.click(await screen.findByText('German'));

    const save = screen.getByRole('button', { name: 'Save Changes' });
    await waitFor(() => expect(save).toBeEnabled());
    await userEvent.click(save);

    expect(router.patch).toHaveBeenCalledWith(
      '/company/projects/7/settings',
      expect.objectContaining({
        project: expect.objectContaining({ preferredArtifactsLanguage: 'de' }),
      }),
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('trims surrounding whitespace from the description before submitting', async () => {
    renderAuthedPage(<SettingsPage />, { props: { project, concurrency } });

    const description = screen.getByLabelText('Description');
    await userEvent.clear(description);
    await userEvent.type(description, '  padded description  ');

    const save = screen.getByRole('button', { name: 'Save Changes' });
    await waitFor(() => expect(save).toBeEnabled());
    await userEvent.click(save);

    expect(router.patch).toHaveBeenCalledWith(
      '/company/projects/7/settings',
      expect.objectContaining({
        project: expect.objectContaining({ description: 'padded description' }),
      }),
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('shows a success notification and the Saved chip when the settings patch resolves', async () => {
    const showSpy = vi.spyOn(notifications, 'show').mockImplementation(() => '');
    renderAuthedPage(<SettingsPage />, { props: { project, concurrency } });

    const nameInput = screen.getByLabelText('Project Name');
    await userEvent.clear(nameInput);
    await userEvent.type(nameInput, 'Renamed Gateway');
    await userEvent.click(screen.getByRole('button', { name: 'Save Changes' }));

    const options = (router.patch as ReturnType<typeof vi.fn>).mock.calls[0][2];
    act(() => options.onSuccess?.());

    expect(showSpy).toHaveBeenCalledWith(
      expect.objectContaining({ message: 'Project settings saved', color: 'green' }),
    );
    expect(screen.getByText('Saved')).toBeInTheDocument();
  });

  it('hides the Saved chip when the form is edited after a successful save', async () => {
    renderAuthedPage(<SettingsPage />, { props: { project, concurrency } });

    const nameInput = screen.getByLabelText('Project Name');
    await userEvent.clear(nameInput);
    await userEvent.type(nameInput, 'Renamed Gateway');
    await userEvent.click(screen.getByRole('button', { name: 'Save Changes' }));

    const options = (router.patch as ReturnType<typeof vi.fn>).mock.calls[0][2];
    act(() => options.onSuccess?.());

    expect(screen.getByText('Saved')).toBeInTheDocument();

    const descriptionInput = screen.getByLabelText('Description');
    await userEvent.clear(descriptionInput);
    await userEvent.type(descriptionInput, 'New description');

    expect(screen.queryByText('Saved')).not.toBeInTheDocument();
  });

  it('shows an error notification when the settings patch fails', async () => {
    const showSpy = vi.spyOn(notifications, 'show').mockImplementation(() => '');
    renderAuthedPage(<SettingsPage />, { props: { project, concurrency } });

    const nameInput = screen.getByLabelText('Project Name');
    await userEvent.clear(nameInput);
    await userEvent.type(nameInput, 'Renamed Gateway');
    await userEvent.click(screen.getByRole('button', { name: 'Save Changes' }));

    const options = (router.patch as ReturnType<typeof vi.fn>).mock.calls[0][2];
    act(() => options.onError?.());

    expect(showSpy).toHaveBeenCalledWith(expect.objectContaining({ message: 'Failed to save settings', color: 'red' }));
  });

  it('opens a confirmation modal when Archive is clicked in the Danger Zone', async () => {
    renderAuthedPage(<SettingsPage />, { props: { project, concurrency } });

    await userEvent.click(screen.getByRole('button', { name: 'Archive' }));

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText(/will be hidden from the sidebar/i)).toBeInTheDocument();
  });

  it('submits a patch that archives the project after confirming the Archive modal', async () => {
    renderAuthedPage(<SettingsPage />, { props: { project, concurrency } });

    await userEvent.click(screen.getByRole('button', { name: 'Archive' }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Archive' }));

    expect(router.patch).toHaveBeenCalledWith(
      '/company/projects/7/settings',
      expect.objectContaining({ project: { state: 'archived' } }),
      expect.objectContaining({ onSuccess: expect.any(Function) }),
    );
  });

  it('notifies and returns to the projects list after the archive patch succeeds', async () => {
    const showSpy = vi.spyOn(notifications, 'show').mockImplementation(() => '');
    renderAuthedPage(<SettingsPage />, { props: { project, concurrency } });

    await userEvent.click(screen.getByRole('button', { name: 'Archive' }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Archive' }));

    const options = (router.patch as ReturnType<typeof vi.fn>).mock.calls[0][2];
    act(() => options.onSuccess?.());

    expect(showSpy).toHaveBeenCalledWith(expect.objectContaining({ message: 'Project archived', color: 'red' }));
    expect(router.visit).toHaveBeenCalledWith('/company/projects');
  });

  it('shows an error notification and stays put when the archive patch fails', async () => {
    const showSpy = vi.spyOn(notifications, 'show').mockImplementation(() => '');
    renderAuthedPage(<SettingsPage />, { props: { project, concurrency } });

    await userEvent.click(screen.getByRole('button', { name: 'Archive' }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Archive' }));

    const options = (router.patch as ReturnType<typeof vi.fn>).mock.calls[0][2];
    act(() => options.onError?.());

    expect(showSpy).toHaveBeenCalledWith(
      expect.objectContaining({ message: 'Failed to archive project', color: 'red' }),
    );
    expect(router.visit).not.toHaveBeenCalled();
  });

  it('opens a confirmation modal when Delete is clicked in the Danger Zone', async () => {
    renderAuthedPage(<SettingsPage />, { props: { project, concurrency } });

    await userEvent.click(screen.getByRole('button', { name: 'Delete' }));

    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByRole('button', { name: 'Delete project' })).toBeDisabled();
  });

  it('issues a delete request after confirming the Delete modal', async () => {
    renderAuthedPage(<SettingsPage />, { props: { project, concurrency } });

    await userEvent.click(screen.getByRole('button', { name: 'Delete' }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.type(within(dialog).getByLabelText('Project name'), 'Gateway Service');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Delete project' }));

    expect(router.delete).toHaveBeenCalledWith(
      '/company/projects/7',
      expect.objectContaining({ onSuccess: expect.any(Function) }),
    );
  });

  it('notifies and returns to the projects list after the delete succeeds', async () => {
    const showSpy = vi.spyOn(notifications, 'show').mockImplementation(() => '');
    renderAuthedPage(<SettingsPage />, { props: { project, concurrency } });

    await userEvent.click(screen.getByRole('button', { name: 'Delete' }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.type(within(dialog).getByLabelText('Project name'), 'Gateway Service');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Delete project' }));

    const options = (router.delete as ReturnType<typeof vi.fn>).mock.calls[0][1];
    act(() => options.onSuccess?.());

    expect(showSpy).toHaveBeenCalledWith(expect.objectContaining({ message: 'Project deleted', color: 'red' }));
    expect(router.visit).toHaveBeenCalledWith('/company/projects');
  });

  it('shows an error notification and stays put when the delete fails', async () => {
    const showSpy = vi.spyOn(notifications, 'show').mockImplementation(() => '');
    renderAuthedPage(<SettingsPage />, { props: { project, concurrency } });

    await userEvent.click(screen.getByRole('button', { name: 'Delete' }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.type(within(dialog).getByLabelText('Project name'), 'Gateway Service');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Delete project' }));

    const options = (router.delete as ReturnType<typeof vi.fn>).mock.calls[0][1];
    act(() => options.onError?.());

    expect(showSpy).toHaveBeenCalledWith(
      expect.objectContaining({ message: 'Failed to delete project', color: 'red' }),
    );
    expect(router.visit).not.toHaveBeenCalled();
  });

  it('hides the Delete control when the user cannot delete the project', () => {
    renderAuthedPage(<SettingsPage />, {
      props: { concurrency, project: { ...project, canDelete: false } },
    });

    expect(screen.getByText('Danger Zone')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Delete' })).not.toBeInTheDocument();
  });

  it('renders an empty Description field when the project has no description', () => {
    renderAuthedPage(<SettingsPage />, {
      props: { concurrency, project: { ...project, description: null } },
    });

    expect(screen.getByLabelText('Description')).toHaveValue('');
  });

  it('defaults the Artifacts Language to English when the project has none set', () => {
    renderAuthedPage(<SettingsPage />, {
      props: { concurrency, project: { ...project, preferredArtifactsLanguage: '' } },
    });

    expect(screen.getByDisplayValue('English')).toBeInTheDocument();
  });

  it('renders the Paused status label for a paused project', () => {
    renderAuthedPage(<SettingsPage />, {
      props: { concurrency, project: { ...project, state: 'paused' } },
    });

    expect(screen.getByText('Paused')).toBeInTheDocument();
  });

  it('renders the Archived status label for an archived project', () => {
    renderAuthedPage(<SettingsPage />, {
      props: { concurrency, project: { ...project, state: 'archived' } },
    });

    expect(screen.getByText('Archived')).toBeInTheDocument();
  });

  it('falls back to the raw state label for an unknown project state', () => {
    renderAuthedPage(<SettingsPage />, {
      props: { concurrency, project: { ...project, state: 'mystery' } },
    });

    expect(screen.getByText('mystery')).toBeInTheDocument();
  });

  it('renders a copy control next to the slug', async () => {
    renderAuthedPage(<SettingsPage />, { props: { project, concurrency } });

    const slug = screen.getByText('gateway-service');
    const slugRow = slug.parentElement as HTMLElement;
    const copyBtn = within(slugRow).getByRole('button');

    await userEvent.click(copyBtn);

    expect(screen.getByText('gateway-service')).toBeInTheDocument();
  });

  describe('concurrent sessions', () => {
    it('submits the limit alongside the rest of the settings', async () => {
      renderAuthedPage(<SettingsPage />, { props: { project, concurrency } });

      const limit = screen.getByLabelText('Concurrent Sessions');
      await userEvent.clear(limit);
      await userEvent.type(limit, '6');

      const save = screen.getByRole('button', { name: 'Save Changes' });
      await waitFor(() => expect(save).toBeEnabled());
      await userEvent.click(save);

      expect(router.patch).toHaveBeenCalledWith(
        '/company/projects/7/settings',
        expect.objectContaining({ concurrency: '6' }),
        expect.objectContaining({ preserveScroll: true }),
      );
    });

    it('sends an empty limit when the field is cleared, which drops the reservation', async () => {
      renderAuthedPage(<SettingsPage />, { props: { project, concurrency: { ...concurrency, maxSessions: 6 } } });

      const limit = screen.getByLabelText('Concurrent Sessions');
      await userEvent.clear(limit);

      const save = screen.getByRole('button', { name: 'Save Changes' });
      await waitFor(() => expect(save).toBeEnabled());
      await userEvent.click(save);

      expect(router.patch).toHaveBeenCalledWith(
        '/company/projects/7/settings',
        expect.objectContaining({ concurrency: '' }),
        expect.anything(),
      );
    });

    it('shows the server refusal against the field', () => {
      renderAuthedPage(<SettingsPage />, {
        props: {
          project,
          concurrency,
          errors: { concurrency: '9 exceeds the company limit of 10 concurrent sessions.' },
        },
      });

      expect(screen.getByText(/exceeds the company limit of 10/)).toBeInTheDocument();
    });

    it("reports how much of the company's limit is left, and to whom", () => {
      renderAuthedPage(<SettingsPage />, {
        props: {
          project,
          concurrency: {
            ...concurrency,
            companyLimit: 20,
            available: 12,
            allocations: [
              { name: 'Gateway', maxSessions: 3 },
              { name: 'Billing', maxSessions: 5 },
            ],
          },
        },
      });

      expect(screen.getByText(/12 of the company.s 20 is unreserved/)).toBeInTheDocument();
      expect(screen.getByText(/Reserved: Gateway 3, Billing 5/)).toBeInTheDocument();
    });

    it('shows the limit read-only to someone who may not change it', () => {
      renderAuthedPage(<SettingsPage />, {
        props: { project, concurrency: { ...concurrency, canManage: false, maxSessions: 6 } },
      });

      expect(screen.queryByLabelText('Concurrent Sessions')).not.toBeInTheDocument();
      expect(screen.getByText(/only a company admin can change this/)).toBeInTheDocument();
    });
  });
});
