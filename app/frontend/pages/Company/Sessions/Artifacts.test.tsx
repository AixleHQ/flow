import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent } from 'test/renderPage';

import SessionArtifactsPage from './Artifacts';

const session = {
  id: 42,
  agentType: 'researcher',
  state: 'completed',
  artifactsReviewed: false,
  projectName: 'Falcon Initiative',
};

const artifact = (overrides: Record<string, unknown> = {}) => ({
  id: 1,
  name: 'report.pdf',
  folder: null,
  status: 'pending',
  fileSize: 2048,
  contentType: 'application/pdf',
  downloadUrl: 'https://example.com/report.pdf',
  createdAt: '2026-01-01T00:00:00Z',
  ...overrides,
});

describe('Company/Sessions/Artifacts', () => {
  it('renders the heading and empty state when there are no artifacts', () => {
    renderAuthedPage(<SessionArtifactsPage />, {
      props: { session, artifacts: [], alreadyReviewed: false },
    });

    expect(screen.getByText('Session Artifacts')).toBeInTheDocument();
    expect(screen.getByText('No outputs collected from this session.')).toBeInTheDocument();
  });

  it('lists artifacts with their formatted size', () => {
    renderAuthedPage(<SessionArtifactsPage />, {
      props: {
        session,
        artifacts: [
          artifact({ id: 1, name: 'report.pdf', fileSize: 2048 }),
          artifact({ id: 2, name: 'summary.txt', fileSize: 512, contentType: 'text/plain' }),
        ],
        alreadyReviewed: false,
      },
    });

    expect(screen.getByText('report.pdf')).toBeInTheDocument();
    expect(screen.getByText('summary.txt')).toBeInTheDocument();
    expect(screen.getByText('2.0 KB')).toBeInTheDocument();
    expect(screen.getByText('512 B')).toBeInTheDocument();
  });

  it('shows the already-reviewed alert and hides the review actions', () => {
    renderAuthedPage(<SessionArtifactsPage />, {
      props: {
        session,
        artifacts: [artifact({ id: 1, name: 'report.pdf' })],
        alreadyReviewed: true,
      },
    });

    expect(screen.getByText('Outputs for this session have already been reviewed.')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Save selected/ })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Dismiss all' })).not.toBeInTheDocument();
  });

  it('posts the review decisions when saving selected artifacts', async () => {
    renderAuthedPage(<SessionArtifactsPage />, {
      props: {
        session,
        artifacts: [artifact({ id: 1, name: 'report.pdf' }), artifact({ id: 2, name: 'summary.txt' })],
        alreadyReviewed: false,
      },
    });

    await userEvent.click(screen.getByRole('button', { name: 'Save selected (2)' }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/sessions/42/artifacts/review',
      { decisions: { '1': 'save', '2': 'save' } },
      expect.objectContaining({ onFinish: expect.any(Function) }),
    );
  });

  it('navigates back to the session when the back button is clicked', async () => {
    renderAuthedPage(<SessionArtifactsPage />, {
      props: { session, artifacts: [], alreadyReviewed: false },
    });

    await userEvent.click(screen.getByRole('button', { name: 'Back to Session' }));

    expect(router.visit).toHaveBeenCalledWith('/company/sessions/42');
  });

  it('formats large file sizes in megabytes and renders an em dash for missing sizes', () => {
    renderAuthedPage(<SessionArtifactsPage />, {
      props: {
        session,
        artifacts: [
          artifact({ id: 1, name: 'video.mp4', fileSize: 3 * 1024 * 1024 }),
          artifact({ id: 2, name: 'unknown.bin', fileSize: null, contentType: null }),
        ],
        alreadyReviewed: false,
      },
    });

    expect(screen.getByText('3.0 MB')).toBeInTheDocument();
    // null fileSize → em dash for the size cell; null contentType → em dash for the type cell
    expect(screen.getAllByText('—').length).toBeGreaterThanOrEqual(2);
  });

  it('shows the session id in the header', () => {
    renderAuthedPage(<SessionArtifactsPage />, {
      props: { session, artifacts: [], alreadyReviewed: false },
    });

    expect(screen.getByText('#42')).toBeInTheDocument();
  });

  it('renders the saved badge only for active artifacts', () => {
    renderAuthedPage(<SessionArtifactsPage />, {
      props: {
        session,
        artifacts: [
          artifact({ id: 1, name: 'active.pdf', status: 'active' }),
          artifact({ id: 2, name: 'pending.pdf', status: 'pending' }),
        ],
        alreadyReviewed: false,
      },
    });

    expect(screen.getByText('saved')).toBeInTheDocument();
  });

  it('renders a download link pointing at the artifact url and omits it when absent', () => {
    renderAuthedPage(<SessionArtifactsPage />, {
      props: {
        session,
        artifacts: [
          artifact({ id: 1, name: 'with-link.pdf', downloadUrl: 'https://example.com/file.pdf' }),
          artifact({ id: 2, name: 'no-link.pdf', downloadUrl: null }),
        ],
        alreadyReviewed: false,
      },
    });

    // The layout chrome renders its own nav links, so scope by the artifact href.
    const downloadLinks = screen
      .getAllByRole('link')
      .filter((el) => el.getAttribute('href') === 'https://example.com/file.pdf');
    expect(downloadLinks).toHaveLength(1);
    expect(downloadLinks[0]).toHaveAttribute('target', '_blank');
    expect(downloadLinks[0]).toHaveAttribute('rel', 'noreferrer');
  });

  it('starts with every artifact selected so the save count matches the total', () => {
    renderAuthedPage(<SessionArtifactsPage />, {
      props: {
        session,
        artifacts: [artifact({ id: 1 }), artifact({ id: 2 }), artifact({ id: 3 })],
        alreadyReviewed: false,
      },
    });

    expect(screen.getByRole('button', { name: 'Save selected (3)' })).toBeEnabled();
    expect(screen.getByRole('checkbox', { name: 'Select all' })).toBeChecked();
  });

  it('decrements the save count and posts a mixed decision when one artifact is deselected', async () => {
    renderAuthedPage(<SessionArtifactsPage />, {
      props: {
        session,
        artifacts: [artifact({ id: 1, name: 'keep.pdf' }), artifact({ id: 2, name: 'drop.pdf' })],
        alreadyReviewed: false,
      },
    });

    await userEvent.click(screen.getByRole('checkbox', { name: 'Select drop.pdf' }));

    const saveBtn = screen.getByRole('button', { name: 'Save selected (1)' });
    expect(saveBtn).toBeEnabled();

    await userEvent.click(saveBtn);

    expect(router.post).toHaveBeenCalledWith(
      '/company/sessions/42/artifacts/review',
      { decisions: { '1': 'save', '2': 'dismiss' } },
      expect.objectContaining({ onFinish: expect.any(Function) }),
    );
  });

  it('puts the select-all checkbox into an indeterminate state when only some rows are selected', async () => {
    renderAuthedPage(<SessionArtifactsPage />, {
      props: {
        session,
        artifacts: [artifact({ id: 1, name: 'a.pdf' }), artifact({ id: 2, name: 'b.pdf' })],
        alreadyReviewed: false,
      },
    });

    const selectAll = screen.getByRole('checkbox', { name: 'Select all' });
    expect(selectAll).toBeChecked();

    await userEvent.click(screen.getByRole('checkbox', { name: 'Select a.pdf' }));

    expect(selectAll).not.toBeChecked();
    expect(selectAll).toBePartiallyChecked();
  });

  it('disables the save button when all artifacts are deselected via select-all', async () => {
    renderAuthedPage(<SessionArtifactsPage />, {
      props: {
        session,
        artifacts: [artifact({ id: 1, name: 'a.pdf' }), artifact({ id: 2, name: 'b.pdf' })],
        alreadyReviewed: false,
      },
    });

    await userEvent.click(screen.getByRole('checkbox', { name: 'Select all' }));

    expect(screen.getByRole('button', { name: 'Save selected (0)' })).toBeDisabled();
  });

  it('re-selects every artifact when select-all is toggled back on', async () => {
    renderAuthedPage(<SessionArtifactsPage />, {
      props: {
        session,
        artifacts: [artifact({ id: 1, name: 'a.pdf' }), artifact({ id: 2, name: 'b.pdf' })],
        alreadyReviewed: false,
      },
    });

    const selectAll = screen.getByRole('checkbox', { name: 'Select all' });
    await userEvent.click(selectAll); // deselect all
    expect(screen.getByRole('button', { name: 'Save selected (0)' })).toBeDisabled();

    await userEvent.click(selectAll); // re-select all
    expect(screen.getByRole('button', { name: 'Save selected (2)' })).toBeEnabled();
    expect(screen.getByRole('checkbox', { name: 'Select a.pdf' })).toBeChecked();
  });

  it('dismisses every artifact regardless of selection when dismiss-all is clicked', async () => {
    renderAuthedPage(<SessionArtifactsPage />, {
      props: {
        session,
        artifacts: [artifact({ id: 1, name: 'a.pdf' }), artifact({ id: 2, name: 'b.pdf' })],
        alreadyReviewed: false,
      },
    });

    // deselect one to prove dismiss_all ignores the current selection
    await userEvent.click(screen.getByRole('checkbox', { name: 'Select a.pdf' }));
    await userEvent.click(screen.getByRole('button', { name: 'Dismiss all' }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/sessions/42/artifacts/review',
      { decisions: { '1': 'dismiss', '2': 'dismiss' } },
      expect.objectContaining({ onFinish: expect.any(Function) }),
    );
  });

  it('hides the row checkboxes when the session has already been reviewed', () => {
    renderAuthedPage(<SessionArtifactsPage />, {
      props: {
        session,
        artifacts: [artifact({ id: 1, name: 'report.pdf', status: 'active' })],
        alreadyReviewed: true,
      },
    });

    expect(screen.queryByRole('checkbox')).not.toBeInTheDocument();
    expect(screen.getByText('report.pdf')).toBeInTheDocument();
    expect(screen.getByText('saved')).toBeInTheDocument();
  });
});
