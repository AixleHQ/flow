import '@testing-library/jest-dom/vitest';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent } from 'test/renderPage';

import { postNavigate } from 'shared/lib/postNavigate';

import TeamsLink from './TeamsLink';

vi.mock('shared/lib/postNavigate', () => ({ postNavigate: vi.fn() }));

describe('TeamsLink', () => {
  it('says whose account Teams will act as, and proves the Teams account with a Microsoft sign-in', async () => {
    renderPage(
      <TeamsLink
        state="ready"
        workspace="Acme"
        account={{ name: 'Ada Lovelace', email: 'ada@acme.test' }}
        signInUrl="/integrations/teams/link/abc/sign_in"
      />,
      { props: { flash: {} } },
    );

    expect(screen.getByText(/start Acme workflows as/)).toHaveTextContent('Ada Lovelace (ada@acme.test)');
    await userEvent.click(screen.getByRole('button', { name: 'Sign in with Microsoft to link' }));
    expect(postNavigate).toHaveBeenCalledWith('/integrations/teams/link/abc/sign_in');
  });

  it('asks a visitor who is not signed in to sign in to Aixle first', () => {
    renderPage(<TeamsLink state="sign_in" loginUrl="/login" />, { props: { flash: {} } });

    expect(screen.getByRole('link', { name: 'Sign in to Aixle' })).toHaveAttribute('href', '/login');
  });

  it('shows why a link cannot be used', () => {
    renderPage(<TeamsLink state="other_company" workspace="Acme" />, {
      props: { flash: { alert: 'That Microsoft account is not the Teams account that asked for this link.' } },
    });

    expect(screen.getByRole('heading', { name: 'Switch to Acme' })).toBeInTheDocument();
    expect(screen.getByText(/not the Teams account that asked/)).toBeInTheDocument();
  });
});
