import '@testing-library/jest-dom/vitest';
import { describe, expect, it, vi } from 'vitest';

import { renderPage, screen, userEvent } from 'test/renderPage';

import { postNavigate } from 'shared/lib/postNavigate';

import McpAuthorize from './McpAuthorize';

vi.mock('shared/lib/postNavigate', () => ({ postNavigate: vi.fn() }));

const authorizeParams = {
  responseType: 'code',
  clientId: 'https://claude.ai/oauth/claude-code-client-metadata',
  redirectUri: 'http://localhost:3118/callback',
  codeChallenge: 'x'.repeat(43),
  codeChallengeMethod: 'S256',
  state: 'abc',
};

const ready = {
  state: 'ready' as const,
  client: { name: 'Claude Code', host: 'claude.ai', label: 'Claude Code (claude.ai)', verified: true },
  destination: 'an app on this computer (localhost)',
  onThisComputer: true,
  account: { name: 'Ada Lovelace', email: 'ada@acme.test' },
  companies: ['Acme'],
  excludedCompanies: [],
  authorizeUrl: '/mcp-oauth/authorize',
  authorizeParams,
};

describe('McpAuthorize', () => {
  it('names the app, the account and the companies it will reach, and allows it', async () => {
    renderPage(<McpAuthorize {...ready} />);

    expect(screen.getByRole('heading', { name: 'Connect Claude Code (claude.ai) to Aixle' })).toBeInTheDocument();
    expect(screen.getByText(/will use Aixle as/)).toHaveTextContent('Ada Lovelace (ada@acme.test)');
    expect(screen.getByText('Acme')).toBeInTheDocument();
    expect(
      screen.getByText(/Only allow this if you started connecting from an app on this computer/),
    ).toBeInTheDocument();
    expect(screen.queryByText(/cannot verify this app/)).not.toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Allow' }));
    expect(postNavigate).toHaveBeenCalledWith('/mcp-oauth/authorize', { ...authorizeParams, decision: 'allow' });
  });

  it('denies', async () => {
    renderPage(<McpAuthorize {...ready} />);

    await userEvent.click(screen.getByRole('button', { name: 'Deny' }));
    expect(postNavigate).toHaveBeenLastCalledWith('/mcp-oauth/authorize', { ...authorizeParams, decision: 'deny' });
  });

  it('warns that a self-registered app names itself', () => {
    renderPage(
      <McpAuthorize
        {...ready}
        client={{ name: 'Claude', host: null, label: 'Claude', verified: false }}
        destination="evil.example"
        onThisComputer={false}
      />,
    );

    expect(screen.getByText(/Aixle cannot verify this app/)).toBeInTheDocument();
    expect(screen.getByText(/goes back to/)).toHaveTextContent('evil.example');
  });

  it('says which companies the sign-in leaves out', () => {
    renderPage(<McpAuthorize {...ready} excludedCompanies={['Globex']} />);

    expect(screen.getByText(/Not Globex: it requires a different sign-in method/)).toBeInTheDocument();
  });

  it('asks for the sign-in a company requires when none is reached', () => {
    renderPage(<McpAuthorize state="no_company" excludedCompanies={['Globex']} />);

    expect(screen.getByRole('heading', { name: 'Sign in the way your company requires' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Allow' })).not.toBeInTheDocument();
  });

  it('shows why an app cannot connect', () => {
    renderPage(<McpAuthorize state="invalid" message="This app is not registered with Aixle" />);

    expect(screen.getByRole('heading', { name: 'This app cannot connect' })).toBeInTheDocument();
    expect(screen.getByText('This app is not registered with Aixle')).toBeInTheDocument();
  });
});
