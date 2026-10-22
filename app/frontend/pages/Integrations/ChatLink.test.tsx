import '@testing-library/jest-dom/vitest';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent } from 'test/renderPage';

import { postNavigate } from 'shared/lib/postNavigate';

import ChatLink from './ChatLink';

vi.mock('shared/lib/postNavigate', () => ({ postNavigate: vi.fn() }));

const teams = {
  provider: 'teams' as const,
  messenger: 'Microsoft Teams',
  signInLabel: 'Sign in with Microsoft to link',
};
const slack = { provider: 'slack' as const, messenger: 'Slack', signInLabel: 'Sign in with Slack to link' };

describe('ChatLink', () => {
  it('says whose account the messenger will act as, and proves it with the messenger’s own sign-in', async () => {
    renderPage(
      <ChatLink
        {...teams}
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

  it('names Slack and its sign-in for a Slack link', () => {
    renderPage(
      <ChatLink {...slack} state="ready" workspace="Acme" signInUrl="/integrations/slack/link/abc/sign_in" />,
      {
        props: { flash: {} },
      },
    );

    expect(screen.getByRole('heading', { name: 'Link your Slack account' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Sign in with Slack to link' })).toBeInTheDocument();
  });

  it('asks a visitor who is not signed in to sign in to Aixle first', () => {
    renderPage(<ChatLink {...teams} state="sign_in" loginUrl="/login" />, { props: { flash: {} } });

    expect(screen.getByRole('link', { name: 'Sign in to Aixle' })).toHaveAttribute('href', '/login');
  });

  it('shows why a link cannot be used', () => {
    renderPage(<ChatLink {...teams} state="other_company" workspace="Acme or Globex" />, {
      props: { flash: { alert: 'That Microsoft account is not the Teams account that asked for this link.' } },
    });

    expect(screen.getByRole('heading', { name: 'Switch company in Aixle' })).toBeInTheDocument();
    expect(
      screen.getByText(
        'This Microsoft Teams workspace is connected to Aixle through Acme or Globex. Switch to it in Aixle, then open the link again.',
      ),
    ).toBeInTheDocument();
    expect(screen.getByText(/not the Teams account that asked/)).toBeInTheDocument();
  });

  it('asks to switch company when none of the visitor’s companies connected the workspace', () => {
    renderPage(<ChatLink {...slack} state="other_company" workspace="a company that connected it" />, {
      props: { flash: {} },
    });

    expect(screen.getByRole('heading', { name: 'Switch company in Aixle' })).toBeInTheDocument();
    expect(
      screen.getByText(
        'This Slack workspace is connected to Aixle through a company that connected it. Switch to it in Aixle, then open the link again.',
      ),
    ).toBeInTheDocument();
  });
});
