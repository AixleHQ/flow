import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { buildTemplateSummary } from 'test/factories/template';
import { renderAuthedPage, renderPage, screen, userEvent, waitFor } from 'test/renderPage';

import IndexPage from './IndexPage';

const templates = [
  buildTemplateSummary(),
  buildTemplateSummary({
    slug: 'sentry-remote-mcp',
    name: 'Sentry (remote MCP)',
    kind: 'connector',
    summary: 'Hosted Sentry MCP server.',
    requires: { integrations: [], repositories: [], secrets: [] },
    includes: { mcpServers: 1 },
  }),
];

describe('Templates/IndexPage', () => {
  it('is readable by a guest, in the public shell with a sign-in button', () => {
    renderPage(<IndexPage />, {
      props: { templates, signedIn: false, flash: {}, settings: { domain: 'flow.acme.example' } },
    });

    expect(screen.getByRole('heading', { level: 1, name: 'Templates' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Sign in' })).toHaveAttribute('href', '/login');
    expect(screen.getByText('flow.acme.example')).toBeInTheDocument();
    expect(screen.getByText('2 templates')).toBeInTheDocument();
  });

  it('describes each template by what it includes and what it needs', () => {
    renderAuthedPage(<IndexPage />, { props: { templates, signedIn: true } });

    expect(screen.getByRole('link', { name: 'Dev team SDLC' })).toHaveAttribute('href', '/templates/dev-team-sdlc');
    expect(screen.getByText('4 columns · 1 agent · 1 workflow · 2 steps')).toBeInTheDocument();
    expect(screen.getByText('Needs github, 1 repository, 1 secret')).toBeInTheDocument();
    expect(screen.getByText('Nothing to connect')).toBeInTheDocument();
  });

  it('filters by kind and by search text', async () => {
    renderAuthedPage(<IndexPage />, { props: { templates, signedIn: true } });

    await userEvent.click(screen.getByText('Connectors 1'));
    expect(screen.queryByText('Dev team SDLC')).not.toBeInTheDocument();
    expect(screen.getByText('Sentry (remote MCP)')).toBeInTheDocument();

    await userEvent.click(screen.getByText('All 2'));
    await userEvent.type(screen.getByRole('textbox', { name: 'Search templates' }), 'nothing like this');
    expect(await screen.findByText('No templates match')).toBeInTheDocument();
    await waitFor(() => expect(screen.queryByText('Sentry (remote MCP)')).not.toBeInTheDocument());
  });
});
