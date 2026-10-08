import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderPage, screen, within } from 'test/renderPage';

import ChangelogPage from './ChangelogPage';
import { type ChangelogRelease } from './data/changelog';

const SOURCE_URL = 'https://github.com/AixleHQ/flow/blob/develop/CHANGELOG.md';

const releases: ChangelogRelease[] = [
  {
    version: 'Unreleased',
    date: null,
    url: 'https://github.com/AixleHQ/flow/compare/v1.0.0...develop',
    summary: '',
    changes: [{ kind: 'Fixed', note: null, entries: [{ area: 'Sessions & Runs', text: 'a stuck **Codex** session' }] }],
  },
  {
    version: '1.0.0',
    date: '2026-10-08',
    url: 'https://github.com/AixleHQ/flow/releases/tag/v1.0.0',
    summary: 'The first tagged release.',
    changes: [
      {
        kind: 'Added',
        note: null,
        entries: [
          { area: 'Tasks', text: 'subtasks on the board' },
          { area: null, text: 'Apache License 2.0' },
        ],
      },
      {
        kind: 'Removed',
        note: 'For deployments that ran a build from before this release:',
        entries: [{ area: null, text: '`RAILS_PORT`' }],
      },
    ],
  },
];

function renderChangelog(props: Record<string, unknown> = {}) {
  renderPage(<ChangelogPage />, {
    props: { releases, sourceUrl: SOURCE_URL, settings: { appVersion: '1.0.0' }, ...props },
  });
}

describe('Docs/ChangelogPage', () => {
  it('lists every release, newest first, with its date', () => {
    renderChangelog();

    expect(screen.getByRole('heading', { level: 1, name: 'Changelog' })).toBeInTheDocument();
    expect(screen.getAllByRole('heading', { level: 2 }).map((h) => h.textContent)).toEqual(['Unreleased', 'v1.0.0']);
    expect(screen.getByText('October 8, 2026')).toHaveAttribute('dateTime', '2026-10-08');
    expect(screen.getByText('The first tagged release.')).toBeInTheDocument();
  });

  it('groups a release’s changes by kind, then by product area', () => {
    renderChangelog();

    const release = screen.getByRole('region', { name: 'v1.0.0' });
    expect(
      within(release)
        .getAllByRole('heading', { level: 3 })
        .map((h) => h.textContent),
    ).toEqual(['Added', 'Removed']);
    expect(
      within(release)
        .getAllByRole('heading', { level: 4 })
        .map((h) => h.textContent),
    ).toEqual(['Tasks', 'Platform & repository']);
    expect(within(release).getByText('Subtasks on the board')).toBeInTheDocument();
    expect(within(release).getByText('For deployments that ran a build from before this release:')).toBeInTheDocument();
    expect(within(release).getByText('RAILS_PORT')).toBeInTheDocument();
  });

  it('marks the unreleased changes, the latest release and the one this installation runs', () => {
    renderChangelog();

    const unreleased = screen.getByRole('region', { name: 'Unreleased' });
    expect(within(unreleased).getByText('Not released yet')).toBeInTheDocument();
    expect(within(unreleased).getByText('Codex')).toBeInTheDocument();

    const latest = screen.getByRole('region', { name: 'v1.0.0' });
    expect(within(latest).getByText('Latest')).toBeInTheDocument();
    expect(within(latest).getByText('Installed')).toBeInTheDocument();
    expect(within(latest).getByRole('link', { name: /View on GitHub/ })).toHaveAttribute(
      'href',
      'https://github.com/AixleHQ/flow/releases/tag/v1.0.0',
    );
  });

  it('does not claim a release is installed when this installation runs another build', () => {
    renderChangelog({ settings: { appVersion: 'unknown' } });

    expect(screen.queryByText('Installed')).not.toBeInTheDocument();
  });

  it('links the source file and marks Changelog as the current section', () => {
    renderChangelog();

    expect(screen.getByRole('link', { name: /CHANGELOG.md on GitHub/ })).toHaveAttribute('href', SOURCE_URL);
    const sections = screen.getByRole('navigation', { name: 'Site sections' });
    expect(within(sections).getByRole('link', { name: 'Changelog' })).toHaveAttribute('aria-current', 'page');
  });

  it('says so when there is nothing to show', () => {
    renderChangelog({ releases: [] });

    expect(screen.getByText('No releases have been published yet.')).toBeInTheDocument();
  });
});
