import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderPage, screen } from 'test/renderPage';

import TeamsApproval from './TeamsApproval';

const pending = {
  state: 'pending' as const,
  workspace: 'Acme',
  requestedBy: { name: 'Ada Lovelace', email: 'ada@acme.test' },
  signInUrl: '/integrations/teams/approve/abc/sign_in',
};

describe('TeamsApproval', () => {
  it('names the workspace and who asked, and signs the administrator in with Microsoft', () => {
    renderPage(<TeamsApproval {...pending} />, { props: { flash: {} } });

    expect(screen.getByRole('heading', { name: 'Connect Microsoft Teams to Acme' })).toBeInTheDocument();
    expect(screen.getByText(/Ada Lovelace \(ada@acme\.test\) asked to connect/)).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Sign in with Microsoft to approve' })).toHaveAttribute(
      'href',
      '/integrations/teams/approve/abc/sign_in',
    );
  });

  it('after approval, offers file access and the app package', () => {
    renderPage(
      <TeamsApproval
        state="connected"
        workspace="Acme"
        organization="contoso.com"
        approvedBy="Megan Bowen"
        fileAccess={false}
        fileAccessUrl="/integrations/teams/approve/abc/file_access"
        packageUrl="/integrations/teams/approve/abc/package"
      />,
      { props: { flash: { notice: 'Connected.' } } },
    );

    expect(screen.getByRole('heading', { name: 'contoso.com is connected to Acme' })).toBeInTheDocument();
    expect(screen.getByText('Connected.')).toBeInTheDocument();
    expect(screen.getByText('Not granted')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Grant file access' })).toHaveAttribute(
      'href',
      '/integrations/teams/approve/abc/file_access',
    );
    expect(screen.getByRole('link', { name: 'Download the Teams app' })).toHaveAttribute(
      'href',
      '/integrations/teams/approve/abc/package',
    );
  });

  it('a stale link says so', () => {
    renderPage(<TeamsApproval state="expired" />, {
      props: { flash: { alert: 'This Microsoft sign-in link was already used' } },
    });

    expect(screen.getByRole('heading', { name: 'This approval link is no longer valid' })).toBeInTheDocument();
    expect(screen.getByText('This Microsoft sign-in link was already used')).toBeInTheDocument();
  });
});
