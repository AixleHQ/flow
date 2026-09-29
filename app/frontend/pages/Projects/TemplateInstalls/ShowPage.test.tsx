import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent } from 'test/renderPage';

import ShowPage from './ShowPage';

const item = (overrides: Record<string, unknown> = {}) => ({
  id: 1,
  kind: 'secret',
  ref: 'secret:SENTRY_TOKEN',
  status: 'pending',
  label: 'Add the secret SENTRY_TOKEN',
  detail: { name: 'SENTRY_TOKEN', description: 'Sentry auth token.' },
  ...overrides,
});

const props = (items: unknown[]) => ({
  project: { id: 5, name: 'Delivery' },
  install: { id: 9, name: 'Dev team SDLC', version: 3, setup: 'Connect GitHub first.' },
  items,
  repositories: [{ id: 2, fullName: 'acme/app' }],
  integrationsPath: '/company/projects/5/integrations',
  mcpServersPath: '/company/projects/5/mcp_servers',
});

const itemUrl = (id: number) => `/company/projects/5/template_installs/9/setup_items/${id}`;

describe('Projects/TemplateInstalls/ShowPage', () => {
  it('saves a secret from the checklist', async () => {
    renderAuthedPage(<ShowPage />, { props: props([item()]) });

    expect(screen.getByText('Connect GitHub first.')).toBeInTheDocument();
    await userEvent.type(screen.getByLabelText('Value for SENTRY_TOKEN'), 'tok-1');
    await userEvent.click(screen.getByRole('button', { name: 'Save' }));

    expect(router.patch).toHaveBeenCalledWith(
      itemUrl(1),
      { operation: 'add_secret', value: 'tok-1' },
      expect.anything(),
    );
  });

  it('activates a trigger and shows progress across items', async () => {
    renderAuthedPage(<ShowPage />, {
      props: props([
        item({
          id: 2,
          kind: 'trigger',
          ref: 'trigger:0',
          label: 'Activate the column trigger of delivery',
          detail: {},
        }),
        item({ id: 3, status: 'done' }),
      ]),
    });

    expect(screen.getByText('1 of 2 done')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Activate' }));

    expect(router.patch).toHaveBeenCalledWith(itemUrl(2), { operation: 'activate' }, expect.anything());
  });

  it('points an integration item at the integrations page', () => {
    renderAuthedPage(<ShowPage />, {
      props: props([item({ id: 4, kind: 'integration', label: 'Connect Github', detail: { provider: 'github' } })]),
    });

    expect(screen.getByRole('link', { name: 'Connect' })).toHaveAttribute('href', '/company/projects/5/integrations');
  });
});
