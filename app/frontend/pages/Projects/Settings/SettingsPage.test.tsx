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
  sessionsCount: 3,
  workflowsCount: 2,
  boardTasksCount: 5,
  repositoriesCount: 1,
  integrationsCount: 4,
  canDelete: true,
};

const members = [
  { id: 1, name: 'Dana Owner', email: 'dana@example.com', isOwner: true },
  { id: 2, name: 'Rory Member', email: 'rory@example.com', isOwner: false },
];

describe('Projects/Settings/SettingsPage', () => {
  it('renders the page title, section headings, and project info from seeded props', () => {
    renderAuthedPage(<SettingsPage />, { props: { project, members } });

    expect(screen.getByText('Project Settings')).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'General' })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Danger Zone' })).toBeInTheDocument();
    // Slug shown verbatim and status badge reflects the active state.
    expect(screen.getByText('gateway-service')).toBeInTheDocument();
    expect(screen.getByText('Active')).toBeInTheDocument();
  });

  it('lists project members with owner/member badges', () => {
    renderAuthedPage(<SettingsPage />, { props: { project, members } });

    const membersHeading = screen.getByRole('heading', { name: 'Members' });
    const membersCard = membersHeading.closest('.mantine-Card-root') as HTMLElement;

    expect(within(membersCard).getByText('Dana Owner')).toBeInTheDocument();
    expect(within(membersCard).getByText('Rory Member')).toBeInTheDocument();
    expect(within(membersCard).getByText('Owner')).toBeInTheDocument();
    expect(within(membersCard).getByText('Member')).toBeInTheDocument();
  });

  it('navigates to integrations when the Integrations quick link is clicked', async () => {
    renderAuthedPage(<SettingsPage />, { props: { project, members } });

    await userEvent.click(screen.getByText('Integrations'));

    expect(router.visit).toHaveBeenCalledWith('/company/projects/7/integrations');
  });

  it('navigates to repositories when the Repositories quick link is clicked', async () => {
    renderAuthedPage(<SettingsPage />, { props: { project, members } });

    await userEvent.click(screen.getByText('Repositories'));

    expect(router.visit).toHaveBeenCalledWith('/company/projects/7/repositories');
  });

  it('disables Save until the form is edited, then submits a patch with the trimmed values', async () => {
    renderAuthedPage(<SettingsPage />, { props: { project, members } });

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
        project: expect.objectContaining({ name: 'Renamed Gateway', preferredArtifactsLanguage: 'en' }),
      }),
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('opens a confirmation modal when Delete is clicked in the Danger Zone', async () => {
    renderAuthedPage(<SettingsPage />, { props: { project, members } });

    await userEvent.click(screen.getByRole('button', { name: 'Delete' }));

    // Confirm modal renders with its own title and a confirm action that stays
    // disabled until the project name is typed back.
    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByRole('button', { name: 'Delete project' })).toBeDisabled();
  });

  it('renders the existing description and selected language in the General form', () => {
    renderAuthedPage(<SettingsPage />, { props: { project, members } });

    expect(screen.getByLabelText('Project Name')).toHaveValue('Gateway Service');
    expect(screen.getByLabelText('Description')).toHaveValue('Edge routing layer');
    // The Select renders its current value's label, English, in the input.
    expect(screen.getByDisplayValue('English')).toBeInTheDocument();
  });

  it('shows the connection counts when integrations and repos are present', () => {
    renderAuthedPage(<SettingsPage />, { props: { project, members } });

    // integrationsCount: 4 -> "4 connected"; repositoriesCount: 1 -> singular "1 repo".
    expect(screen.getByText('4 connected')).toBeInTheDocument();
    expect(screen.getByText('1 repo')).toBeInTheDocument();
  });

  it('shows empty-state copy in quick links when there are no integrations or repos', () => {
    const empty = { ...project, integrationsCount: 0, repositoriesCount: 0 };
    renderAuthedPage(<SettingsPage />, { props: { project: empty, members } });

    expect(screen.getByText('Not configured')).toBeInTheDocument();
    expect(screen.getByText('No repos added')).toBeInTheDocument();
  });

  it('pluralizes the repositories count for more than one repo', () => {
    const multiRepo = { ...project, repositoriesCount: 3 };
    renderAuthedPage(<SettingsPage />, { props: { project: multiRepo, members } });

    expect(screen.getByText('3 repos')).toBeInTheDocument();
  });

  it('renders the Paused status badge for a paused project', () => {
    const paused = { ...project, state: 'paused' };
    renderAuthedPage(<SettingsPage />, { props: { project: paused, members } });

    expect(screen.getByText('Paused')).toBeInTheDocument();
  });

  it('falls back to the raw state label for an unknown project state', () => {
    const unknown = { ...project, state: 'mystery' };
    renderAuthedPage(<SettingsPage />, { props: { project: unknown, members } });

    expect(screen.getByText('mystery')).toBeInTheDocument();
  });

  it('renders the formatted created date and project stat values', () => {
    renderAuthedPage(<SettingsPage />, { props: { project, members } });

    // createdAt 2026-01-01 formatted as a long en-US date.
    expect(screen.getByText('January 1, 2026')).toBeInTheDocument();

    // Stats grid: scope to the Project Info card to avoid colliding with members count.
    const infoHeading = screen.getByRole('heading', { name: 'Project Info' });
    const infoCard = infoHeading.closest('.mantine-Card-root') as HTMLElement;
    expect(within(infoCard).getByText('Sessions')).toBeInTheDocument();
    expect(within(infoCard).getByText('Workflows')).toBeInTheDocument();
    expect(within(infoCard).getByText('Tasks')).toBeInTheDocument();
  });

  it('renders the owner name and email in the Project Info card', () => {
    renderAuthedPage(<SettingsPage />, { props: { project, members } });

    const infoHeading = screen.getByRole('heading', { name: 'Project Info' });
    const infoCard = infoHeading.closest('.mantine-Card-root') as HTMLElement;

    expect(within(infoCard).getByText('Dana Owner')).toBeInTheDocument();
    expect(within(infoCard).getByText('dana@example.com')).toBeInTheDocument();
  });

  it('renders a copy control next to the slug and keeps the slug visible after clicking it', async () => {
    renderAuthedPage(<SettingsPage />, { props: { project, members } });

    // The copy button has no accessible name; it lives next to the slug text.
    const slug = screen.getByText('gateway-service');
    const slugRow = slug.parentElement as HTMLElement;
    const copyBtn = within(slugRow).getByRole('button');

    // Clicking exercises the CopyButton render-prop branch without throwing in jsdom.
    await userEvent.click(copyBtn);

    expect(screen.getByText('gateway-service')).toBeInTheDocument();
  });

  it('shows the singular member count label when there is exactly one member', () => {
    const oneMember = [{ id: 1, name: 'Solo Dev', email: 'solo@example.com', isOwner: true }];
    renderAuthedPage(<SettingsPage />, { props: { project, members: oneMember } });

    expect(screen.getByText('1 member')).toBeInTheDocument();
  });

  it('keeps Save disabled when the name is cleared to whitespace only', async () => {
    renderAuthedPage(<SettingsPage />, { props: { project, members } });

    const nameInput = screen.getByLabelText('Project Name');
    await userEvent.clear(nameInput);
    await userEvent.type(nameInput, '   ');

    expect(screen.getByRole('button', { name: 'Save Changes' })).toBeDisabled();
    expect(router.patch).not.toHaveBeenCalled();
  });

  it('submits a patch that archives the project after confirming the Archive modal', async () => {
    renderAuthedPage(<SettingsPage />, { props: { project, members } });

    await userEvent.click(screen.getByRole('button', { name: 'Archive' }));

    // The confirm modal exposes its own "Archive" confirm action plus the modal body text.
    // Both the Danger Zone and the modal have an "Archive" button, so scope to the dialog.
    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText(/will be hidden from the sidebar/i)).toBeInTheDocument();
    const confirm = within(dialog).getByRole('button', { name: 'Archive' });

    await userEvent.click(confirm);

    expect(router.patch).toHaveBeenCalledWith(
      '/company/projects/7/settings',
      expect.objectContaining({ project: { state: 'archived' } }),
      expect.objectContaining({ onSuccess: expect.any(Function) }),
    );
  });

  it('issues a delete request after confirming the Delete modal', async () => {
    renderAuthedPage(<SettingsPage />, { props: { project, members } });

    await userEvent.click(screen.getByRole('button', { name: 'Delete' }));

    // "cannot be undone" appears in both the Danger Zone blurb and the modal, so scope to the dialog.
    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText(/cannot be undone/i)).toBeInTheDocument();

    // Type-to-confirm: the button only arms once the name matches exactly.
    await userEvent.type(within(dialog).getByLabelText(/type "gateway service" to confirm/i), 'Gateway Service');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Delete project' }));

    expect(router.delete).toHaveBeenCalledWith(
      '/company/projects/7',
      expect.objectContaining({ onSuccess: expect.any(Function) }),
    );
  });

  it('hides the Delete control when the user cannot delete the project', () => {
    renderAuthedPage(<SettingsPage />, { props: { project: { ...project, canDelete: false }, members } });

    // Danger Zone still renders (Archive lives there), but the destructive Delete button is gone.
    expect(screen.getByRole('heading', { name: 'Danger Zone' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Delete' })).not.toBeInTheDocument();
  });

  it('submits the chosen artifacts language after picking a new option', async () => {
    renderAuthedPage(<SettingsPage />, { props: { project, members } });

    // Mantine Select must be clicked to open before an option is selectable.
    await userEvent.click(screen.getByRole('combobox', { name: 'Artifacts Language' }));
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
    renderAuthedPage(<SettingsPage />, { props: { project, members } });

    const description = screen.getByLabelText('Description');
    await userEvent.clear(description);
    await userEvent.type(description, '  padded description  ');

    const save = screen.getByRole('button', { name: 'Save Changes' });
    await waitFor(() => expect(save).toBeEnabled());
    await userEvent.click(save);

    expect(router.patch).toHaveBeenCalledWith(
      '/company/projects/7/settings',
      expect.objectContaining({ project: expect.objectContaining({ description: 'padded description' }) }),
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('shows a success notification when the settings patch resolves', async () => {
    const showSpy = vi.spyOn(notifications, 'show').mockImplementation(() => '');
    renderAuthedPage(<SettingsPage />, { props: { project, members } });

    const nameInput = screen.getByLabelText('Project Name');
    await userEvent.clear(nameInput);
    await userEvent.type(nameInput, 'Renamed Gateway');
    await userEvent.click(screen.getByRole('button', { name: 'Save Changes' }));

    // The inert router mock never resolves, so drive the success path Inertia would have invoked.
    const options = (router.patch as ReturnType<typeof vi.fn>).mock.calls[0][2];
    act(() => options.onSuccess?.());

    expect(showSpy).toHaveBeenCalledWith(
      expect.objectContaining({ message: 'Project settings saved', color: 'green' }),
    );
  });

  it('shows an error notification when the settings patch fails', async () => {
    const showSpy = vi.spyOn(notifications, 'show').mockImplementation(() => '');
    renderAuthedPage(<SettingsPage />, { props: { project, members } });

    const nameInput = screen.getByLabelText('Project Name');
    await userEvent.clear(nameInput);
    await userEvent.type(nameInput, 'Renamed Gateway');
    await userEvent.click(screen.getByRole('button', { name: 'Save Changes' }));

    const options = (router.patch as ReturnType<typeof vi.fn>).mock.calls[0][2];
    act(() => options.onError?.());

    expect(showSpy).toHaveBeenCalledWith(expect.objectContaining({ message: 'Failed to save settings', color: 'red' }));
  });

  it('notifies and returns to the projects list after the archive patch succeeds', async () => {
    const showSpy = vi.spyOn(notifications, 'show').mockImplementation(() => '');
    renderAuthedPage(<SettingsPage />, { props: { project, members } });

    await userEvent.click(screen.getByRole('button', { name: 'Archive' }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Archive' }));

    const options = (router.patch as ReturnType<typeof vi.fn>).mock.calls[0][2];
    act(() => options.onSuccess?.());

    expect(showSpy).toHaveBeenCalledWith(expect.objectContaining({ message: 'Project archived', color: 'orange' }));
    expect(router.visit).toHaveBeenCalledWith('/company/projects');
  });

  it('shows an error notification and stays put when the archive patch fails', async () => {
    const showSpy = vi.spyOn(notifications, 'show').mockImplementation(() => '');
    renderAuthedPage(<SettingsPage />, { props: { project, members } });

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

  it('notifies and returns to the projects list after the delete succeeds', async () => {
    const showSpy = vi.spyOn(notifications, 'show').mockImplementation(() => '');
    renderAuthedPage(<SettingsPage />, { props: { project, members } });

    await userEvent.click(screen.getByRole('button', { name: 'Delete' }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.type(within(dialog).getByLabelText(/type "gateway service" to confirm/i), 'Gateway Service');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Delete project' }));

    // router.delete(url, options) — the callbacks live in the second argument.
    const options = (router.delete as ReturnType<typeof vi.fn>).mock.calls[0][1];
    act(() => options.onSuccess?.());

    expect(showSpy).toHaveBeenCalledWith(expect.objectContaining({ message: 'Project deleted', color: 'red' }));
    expect(router.visit).toHaveBeenCalledWith('/company/projects');
  });

  it('shows an error notification and stays put when the delete fails', async () => {
    const showSpy = vi.spyOn(notifications, 'show').mockImplementation(() => '');
    renderAuthedPage(<SettingsPage />, { props: { project, members } });

    await userEvent.click(screen.getByRole('button', { name: 'Delete' }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.type(within(dialog).getByLabelText(/type "gateway service" to confirm/i), 'Gateway Service');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Delete project' }));

    const options = (router.delete as ReturnType<typeof vi.fn>).mock.calls[0][1];
    act(() => options.onError?.());

    expect(showSpy).toHaveBeenCalledWith(
      expect.objectContaining({ message: 'Failed to delete project', color: 'red' }),
    );
    expect(router.visit).not.toHaveBeenCalled();
  });

  it('renders an empty Description field when the project has no description', () => {
    const noDescription = { ...project, description: null };
    renderAuthedPage(<SettingsPage />, { props: { project: noDescription, members } });

    expect(screen.getByLabelText('Description')).toHaveValue('');
  });

  it('defaults the Artifacts Language to English when the project has none set', () => {
    const noLanguage = { ...project, preferredArtifactsLanguage: '' };
    renderAuthedPage(<SettingsPage />, { props: { project: noLanguage, members } });

    // The useForm fallback (preferredArtifactsLanguage || 'en') resolves to the English label.
    expect(screen.getByDisplayValue('English')).toBeInTheDocument();
  });

  it('renders the Archived status badge for an archived project', () => {
    const archived = { ...project, state: 'archived' };
    renderAuthedPage(<SettingsPage />, { props: { project: archived, members } });

    expect(screen.getByText('Archived')).toBeInTheDocument();
  });
});
