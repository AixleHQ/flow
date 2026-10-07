import '@testing-library/jest-dom/vitest';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent } from 'test/renderPage';

import { postNavigate } from 'shared/lib/postNavigate';

import TeamsApproval from './TeamsApproval';

vi.mock('shared/lib/postNavigate', () => ({ postNavigate: vi.fn() }));

const pending = {
  state: 'pending' as const,
  workspace: 'Acme',
  requestedBy: { name: 'Ada Lovelace', email: 'ada@acme.test' },
  signInUrl: '/integrations/teams/approve/abc/sign_in',
};

describe('TeamsApproval', () => {
  it('names the workspace and who asked, and signs the administrator in with Microsoft by a form post', async () => {
    renderPage(<TeamsApproval {...pending} />, { props: { flash: {} } });

    expect(screen.getByRole('heading', { name: 'Connect Microsoft Teams to Acme' })).toBeInTheDocument();
    expect(screen.getByText(/Ada Lovelace \(ada@acme\.test\) asked to connect/)).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Sign in with Microsoft to approve' }));
    expect(postNavigate).toHaveBeenCalledWith('/integrations/teams/approve/abc/sign_in', { files: '1' });
  });

  it('lets the administrator leave file access out of the one sign-in', async () => {
    renderPage(<TeamsApproval {...pending} />, { props: { flash: {} } });

    await userEvent.click(screen.getByRole('checkbox', { name: /Also give access to files/ }));
    await userEvent.click(screen.getByRole('button', { name: 'Sign in with Microsoft to approve' }));

    expect(postNavigate).toHaveBeenLastCalledWith('/integrations/teams/approve/abc/sign_in', { files: '0' });
  });

  it('after approval, offers file access and the app package', async () => {
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
    await userEvent.click(screen.getByRole('button', { name: 'Grant file access' }));
    expect(postNavigate).toHaveBeenCalledWith('/integrations/teams/approve/abc/file_access');
    expect(screen.getByRole('link', { name: 'Download the Teams app' })).toHaveAttribute(
      'href',
      '/integrations/teams/approve/abc/package',
    );
  });

  it('says the app is already in the organization when the approval published it', () => {
    renderPage(<TeamsApproval state="connected" workspace="Acme" organization="contoso.com" fileAccess published />, {
      props: { flash: {} },
    });

    expect(screen.getByText('Published')).toBeInTheDocument();
    expect(screen.queryByRole('link', { name: 'Download the Teams app' })).not.toBeInTheDocument();
  });

  it('a stale link says so', () => {
    renderPage(<TeamsApproval state="expired" />, {
      props: { flash: { alert: 'This Microsoft sign-in link was already used' } },
    });

    expect(screen.getByRole('heading', { name: 'This approval link is no longer valid' })).toBeInTheDocument();
    expect(screen.getByText('This Microsoft sign-in link was already used')).toBeInTheDocument();
  });
});
