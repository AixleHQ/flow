import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent, waitFor, within } from 'test/renderPage';

import { AddRepositoryModal } from './AddRepositoryModal';

const integration = { id: 7, name: 'Acme Org', provider: 'github', status: 'active' };

describe('AddRepositoryModal', () => {
  it('renders the title and form fields when opened', () => {
    renderPage(
      <AddRepositoryModal
        opened
        onClose={vi.fn()}
        basePath="/projects/1/repositories"
        existingRepoNames={new Set<string>()}
      />,
      { props: { integrations: [] } },
    );

    expect(screen.getByRole('heading', { name: 'Add Repository' })).toBeInTheDocument();
    // Mantine <Select> renders a combobox input; assert by its visible label.
    expect(screen.getByRole('combobox', { name: /integration/i })).toBeInTheDocument();
    expect(screen.getByRole('combobox', { name: /repository/i })).toBeInTheDocument();
    expect(screen.getByRole('combobox', { name: /source branch/i })).toBeInTheDocument();
    expect(screen.getByRole('textbox', { name: /purpose/i })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Add Repository' })).toBeInTheDocument();
  });

  it('shows the "connect one first" placeholder and disables the integration field with no integrations', () => {
    renderPage(
      <AddRepositoryModal
        opened
        onClose={vi.fn()}
        basePath="/projects/1/repositories"
        existingRepoNames={new Set<string>()}
      />,
      { props: { integrations: [] } },
    );

    expect(screen.getByPlaceholderText(/connect one first/i)).toBeDisabled();
  });

  it('auto-selects the sole integration and fires a backend reload for its repos', async () => {
    renderPage(
      <AddRepositoryModal
        opened
        onClose={vi.fn()}
        basePath="/projects/1/repositories"
        existingRepoNames={new Set<string>()}
      />,
      { props: { integrations: [integration] } },
    );

    // With exactly one integration, the component auto-selects it on open and loads its repos.
    await waitFor(() =>
      expect(router.reload).toHaveBeenCalledWith(
        expect.objectContaining({ data: { integration_id: '7' }, only: ['available_repos'] }),
      ),
    );
  });

  it('keeps the Repository field disabled until an integration is chosen', () => {
    renderPage(
      <AddRepositoryModal
        opened
        onClose={vi.fn()}
        basePath="/projects/1/repositories"
        existingRepoNames={new Set<string>()}
      />,
      // Two integrations -> no auto-select, so no integration is chosen yet.
      {
        props: {
          integrations: [integration, { id: 9, name: 'Other Org', provider: 'gitlab', status: 'active' }],
        },
      },
    );

    expect(screen.getByRole('combobox', { name: /repository/i })).toBeDisabled();
  });

  it('lets the user type a purpose without triggering a backend request', async () => {
    renderPage(
      <AddRepositoryModal
        opened
        onClose={vi.fn()}
        basePath="/projects/1/repositories"
        existingRepoNames={new Set<string>()}
      />,
      { props: { integrations: [] } },
    );

    const purpose = screen.getByRole('textbox', { name: /purpose/i });
    await userEvent.type(purpose, 'Main Rails app');

    expect(purpose).toHaveValue('Main Rails app');
    expect(router.post).not.toHaveBeenCalled();
  });

  it('the drawer close button calls onClose', async () => {
    const onClose = vi.fn();
    renderPage(
      <AddRepositoryModal
        opened
        onClose={onClose}
        basePath="/projects/1/repositories"
        existingRepoNames={new Set<string>()}
      />,
      { props: { integrations: [] } },
    );

    await userEvent.click(screen.getByRole('button', { name: 'Close' }));

    expect(onClose).toHaveBeenCalled();
  });

  it('renders a server-error alert when page errors are present', () => {
    renderPage(
      <AddRepositoryModal
        opened
        onClose={vi.fn()}
        basePath="/projects/1/repositories"
        existingRepoNames={new Set<string>()}
      />,
      { props: { integrations: [], errors: { base: 'Repository already connected' } } },
    );

    const alert = screen.getByRole('alert');
    expect(within(alert).getByText('Repository already connected')).toBeInTheDocument();
  });

  it('joins multiple server errors into one alert', () => {
    renderPage(
      <AddRepositoryModal
        opened
        onClose={vi.fn()}
        basePath="/projects/1/repositories"
        existingRepoNames={new Set<string>()}
      />,
      {
        props: {
          integrations: [],
          errors: { full_name: 'is invalid', source_branch: 'is required' },
        },
      },
    );

    const alert = screen.getByRole('alert');
    expect(within(alert).getByText('is invalid, is required')).toBeInTheDocument();
  });

  it('renders no server-error alert when there are no page errors', () => {
    renderPage(
      <AddRepositoryModal
        opened
        onClose={vi.fn()}
        basePath="/projects/1/repositories"
        existingRepoNames={new Set<string>()}
      />,
      { props: { integrations: [] } },
    );

    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
  });

  it('renders nothing when not opened', () => {
    renderPage(
      <AddRepositoryModal
        opened={false}
        onClose={vi.fn()}
        basePath="/projects/1/repositories"
        existingRepoNames={new Set<string>()}
      />,
      { props: { integrations: [] } },
    );

    expect(screen.queryByRole('heading', { name: 'Add Repository' })).not.toBeInTheDocument();
  });

  it('labels GitHub vs GitLab integrations in the dropdown options', async () => {
    renderPage(
      <AddRepositoryModal
        opened
        onClose={vi.fn()}
        basePath="/projects/1/repositories"
        existingRepoNames={new Set<string>()}
      />,
      {
        props: {
          integrations: [integration, { id: 9, name: 'Other Org', provider: 'gitlab', status: 'active' }],
        },
      },
    );

    await userEvent.click(screen.getByRole('combobox', { name: /integration/i }));

    expect(await screen.findByRole('option', { name: 'Acme Org (GitHub)' })).toBeInTheDocument();
    expect(screen.getByRole('option', { name: 'Other Org (GitLab)' })).toBeInTheDocument();
  });

  it('selecting an integration enables the repo field and reloads its repos', async () => {
    renderPage(
      <AddRepositoryModal
        opened
        onClose={vi.fn()}
        basePath="/projects/1/repositories"
        existingRepoNames={new Set<string>()}
      />,
      {
        props: {
          integrations: [integration, { id: 9, name: 'Other Org', provider: 'gitlab', status: 'active' }],
        },
      },
    );

    // Two integrations -> no auto-select; choose one explicitly.
    await userEvent.click(screen.getByRole('combobox', { name: /integration/i }));
    await userEvent.click(await screen.findByRole('option', { name: 'Acme Org (GitHub)' }));

    expect(router.reload).toHaveBeenCalledWith(
      expect.objectContaining({ data: { integration_id: '7' }, only: ['available_repos'] }),
    );
    // While repos are loading the picker shows the loading placeholder (mock never finishes reload).
    expect(screen.getByPlaceholderText('Loading repositories...')).toBeInTheDocument();
  });

  it('excludes already-connected repositories from the repository options', async () => {
    // Let the reload that auto-selecting the sole integration triggers "finish", so the repo
    // picker leaves its loading/disabled state and can be opened.
    vi.mocked(router.reload).mockImplementation((opts) => {
      (opts as { onFinish?: () => void } | undefined)?.onFinish?.();
    });
    renderPage(
      <AddRepositoryModal
        opened
        onClose={vi.fn()}
        basePath="/projects/1/repositories"
        existingRepoNames={new Set(['acme/already-here'])}
      />,
      {
        props: {
          integrations: [integration],
          availableRepos: [
            { fullName: 'acme/already-here', defaultBranch: 'main' },
            { fullName: 'acme/fresh-repo', defaultBranch: 'develop' },
          ],
        },
      },
    );

    // Sole integration auto-selects on open; the repo picker is populated from availableRepos.
    const repoField = await screen.findByRole('combobox', { name: /repository/i });
    await waitFor(() => expect(repoField).toBeEnabled());
    await userEvent.click(repoField);

    expect(await screen.findByRole('option', { name: 'acme/fresh-repo' })).toBeInTheDocument();
    expect(screen.queryByRole('option', { name: 'acme/already-here' })).not.toBeInTheDocument();
  });

  it('selecting a repository prefills its default branch and reloads branches', async () => {
    vi.mocked(router.reload).mockImplementation((opts) => {
      (opts as { onFinish?: () => void } | undefined)?.onFinish?.();
    });
    renderPage(
      <AddRepositoryModal
        opened
        onClose={vi.fn()}
        basePath="/projects/1/repositories"
        existingRepoNames={new Set<string>()}
      />,
      {
        props: {
          integrations: [integration],
          availableRepos: [{ fullName: 'acme/fresh-repo', defaultBranch: 'develop' }],
          // Seed branches so the Select can resolve the prefilled value to its display label.
          availableBranches: ['develop', 'main'],
        },
      },
    );

    const repoField = await screen.findByRole('combobox', { name: /repository/i });
    await waitFor(() => expect(repoField).toBeEnabled());
    await userEvent.click(repoField);
    await userEvent.click(await screen.findByRole('option', { name: 'acme/fresh-repo' }));

    // The default branch is prefilled into the (now-enabled) source-branch field.
    expect(screen.getByRole('combobox', { name: /source branch/i })).toHaveValue('develop');
    // Branches are reloaded for the chosen repo.
    expect(router.reload).toHaveBeenCalledWith(
      expect.objectContaining({
        data: { integration_id: '7', repo: 'acme/fresh-repo' },
        only: ['available_branches'],
      }),
    );
  });

  it('keeps the source-branch field disabled until a repository is chosen', async () => {
    renderPage(
      <AddRepositoryModal
        opened
        onClose={vi.fn()}
        basePath="/projects/1/repositories"
        existingRepoNames={new Set<string>()}
      />,
      { props: { integrations: [integration] } },
    );

    expect(await screen.findByRole('combobox', { name: /source branch/i })).toBeDisabled();
  });

  it('submits the repository payload via router.post once every field is filled', async () => {
    vi.mocked(router.reload).mockImplementation((opts) => {
      (opts as { onFinish?: () => void } | undefined)?.onFinish?.();
    });
    renderPage(
      <AddRepositoryModal
        opened
        onClose={vi.fn()}
        basePath="/projects/1/repositories"
        existingRepoNames={new Set<string>()}
      />,
      {
        props: {
          integrations: [integration],
          availableRepos: [{ fullName: 'acme/fresh-repo', defaultBranch: 'develop' }],
          availableBranches: ['develop', 'main'],
        },
      },
    );

    const repoField = await screen.findByRole('combobox', { name: /repository/i });
    await waitFor(() => expect(repoField).toBeEnabled());
    await userEvent.click(repoField);
    await userEvent.click(await screen.findByRole('option', { name: 'acme/fresh-repo' }));

    // Source branch is prefilled to develop from the repo's defaultBranch, so the form is valid.
    await userEvent.type(screen.getByRole('textbox', { name: /purpose/i }), 'Our main app');
    await userEvent.click(screen.getByRole('button', { name: 'Add Repository' }));

    expect(router.post).toHaveBeenCalledWith(
      '/projects/1/repositories',
      {
        repository: {
          integrationId: 7,
          fullName: 'acme/fresh-repo',
          sourceBranch: 'develop',
          purpose: 'Our main app',
        },
      },
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('swaps the integration pickers for a url field in public mode', async () => {
    renderPage(
      <AddRepositoryModal
        opened
        onClose={vi.fn()}
        basePath="/projects/1/repositories"
        existingRepoNames={new Set<string>()}
      />,
      { props: { integrations: [integration] } },
    );

    await userEvent.click(screen.getByRole('radio', { name: 'Public repository' }));

    expect(screen.getByRole('textbox', { name: /repository url/i })).toBeInTheDocument();
    expect(screen.getByRole('textbox', { name: /^branch/i })).toBeInTheDocument();
    expect(screen.queryByRole('combobox', { name: /integration/i })).not.toBeInTheDocument();
  });

  it('submits a public repository as a url, leaving the branch to the backend', async () => {
    renderPage(
      <AddRepositoryModal
        opened
        onClose={vi.fn()}
        basePath="/projects/1/repositories"
        existingRepoNames={new Set<string>()}
      />,
      { props: { integrations: [] } },
    );

    await userEvent.click(screen.getByRole('radio', { name: 'Public repository' }));
    await userEvent.type(screen.getByRole('textbox', { name: /repository url/i }), 'https://github.com/rails/rails');
    await userEvent.click(screen.getByRole('button', { name: 'Add Repository' }));

    expect(router.post).toHaveBeenCalledWith(
      '/projects/1/repositories',
      { repository: { publicUrl: 'https://github.com/rails/rails', sourceBranch: '', purpose: '' } },
      expect.objectContaining({ preserveScroll: true }),
    );
  });

  it('does not submit a public repository without a url', async () => {
    renderPage(
      <AddRepositoryModal
        opened
        onClose={vi.fn()}
        basePath="/projects/1/repositories"
        existingRepoNames={new Set<string>()}
      />,
      { props: { integrations: [] } },
    );

    await userEvent.click(screen.getByRole('radio', { name: 'Public repository' }));
    await userEvent.click(screen.getByRole('button', { name: 'Add Repository' }));

    expect(await screen.findByText('Repository URL is required')).toBeInTheDocument();
    expect(router.post).not.toHaveBeenCalled();
  });

  it('shows the submit button enabled and labeled before any submission', () => {
    renderPage(
      <AddRepositoryModal
        opened
        onClose={vi.fn()}
        basePath="/projects/1/repositories"
        existingRepoNames={new Set<string>()}
      />,
      { props: { integrations: [] } },
    );

    const submit = screen.getByRole('button', { name: 'Add Repository' });
    expect(submit).toBeEnabled();
    expect(submit).toHaveAttribute('type', 'submit');
  });
});
