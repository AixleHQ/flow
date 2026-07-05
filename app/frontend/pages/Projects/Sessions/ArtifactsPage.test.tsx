import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { buildSessionArtifact } from 'test/factories/sessionArtifact';
import { renderAuthedPage, screen, userEvent } from 'test/renderPage';

import ArtifactsPage from './ArtifactsPage';

const project = { id: 7, name: 'Orbital Launcher' };
const session = { id: 42, state: 'completed', projectId: 7 };

const baseProps = {
  project,
  session,
  artifacts: [buildSessionArtifact()],
  alreadyReviewed: false,
};

describe('Projects/Sessions/ArtifactsPage', () => {
  it('renders the heading and lists the seeded artifacts', () => {
    renderAuthedPage(<ArtifactsPage />, {
      props: {
        ...baseProps,
        artifacts: [
          buildSessionArtifact({ id: 1, name: 'report.pdf' }),
          buildSessionArtifact({ id: 2, name: 'data.csv' }),
        ],
      },
    });

    expect(screen.getByText('Session Artifacts')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Back to Session' })).toBeInTheDocument();
    expect(screen.getByText('report.pdf')).toBeInTheDocument();
    expect(screen.getByText('data.csv')).toBeInTheDocument();
  });

  it('shows the empty state when no artifacts were collected', () => {
    renderAuthedPage(<ArtifactsPage />, { props: { ...baseProps, artifacts: [] } });

    expect(screen.getByText('No outputs collected from this session.')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Save selected/ })).not.toBeInTheDocument();
  });

  it('hides selection controls and shows the reviewed notice when already reviewed', () => {
    renderAuthedPage(<ArtifactsPage />, { props: { ...baseProps, alreadyReviewed: true } });

    expect(screen.getByText('Outputs for this session have already been reviewed.')).toBeInTheDocument();
    expect(screen.queryByRole('checkbox', { name: 'Select all' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /Save selected/ })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Dismiss all' })).not.toBeInTheDocument();
  });

  it('posts the review decisions when "Save selected" is clicked', async () => {
    renderAuthedPage(<ArtifactsPage />, {
      props: {
        ...baseProps,
        artifacts: [buildSessionArtifact({ id: 11, name: 'a.txt' }), buildSessionArtifact({ id: 22, name: 'b.txt' })],
      },
    });

    // All artifacts start selected, so the counter reflects both.
    expect(screen.getByRole('button', { name: 'Save selected (2)' })).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Save selected (2)' }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/7/sessions/42/artifacts/review',
      { decisions: { '11': 'save', '22': 'save' } },
      expect.objectContaining({ onSuccess: expect.any(Function), onFinish: expect.any(Function) }),
    );
  });

  it('updates the selected counter and decisions when a checkbox is unticked', async () => {
    renderAuthedPage(<ArtifactsPage />, {
      props: {
        ...baseProps,
        artifacts: [buildSessionArtifact({ id: 11, name: 'a.txt' }), buildSessionArtifact({ id: 22, name: 'b.txt' })],
      },
    });

    await userEvent.click(screen.getByRole('checkbox', { name: 'Select a.txt' }));

    expect(screen.getByRole('button', { name: 'Save selected (1)' })).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Save selected (1)' }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/7/sessions/42/artifacts/review',
      { decisions: { '11': 'dismiss', '22': 'save' } },
      expect.anything(),
    );
  });

  it('posts dismiss decisions for every artifact when "Dismiss all" is clicked', async () => {
    renderAuthedPage(<ArtifactsPage />, {
      props: {
        ...baseProps,
        artifacts: [buildSessionArtifact({ id: 11, name: 'a.txt' }), buildSessionArtifact({ id: 22, name: 'b.txt' })],
      },
    });

    await userEvent.click(screen.getByRole('button', { name: 'Dismiss all' }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/projects/7/sessions/42/artifacts/review',
      { decisions: { '11': 'dismiss', '22': 'dismiss' } },
      expect.anything(),
    );
  });
});
