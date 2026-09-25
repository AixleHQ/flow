import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import { buildTemplateDetail } from 'test/factories/template';
import { renderAuthedPage, screen, userEvent } from 'test/renderPage';

import InstallPage from './InstallPage';

const plan = (overrides: Record<string, unknown> = {}) => ({
  target: 'new_project',
  projectName: 'Dev team SDLC',
  digest: 'digest-1',
  resolved: true,
  items: [{ section: 'agents', key: 'architect', name: 'architect', action: 'create', installName: 'architect' }],
  boardAction: 'create',
  warnings: [],
  checklist: [{ kind: 'secret', ref: 'secret:SENTRY_TOKEN' }],
  ...overrides,
});

const props = (overrides: Record<string, unknown> = {}) => ({
  template: buildTemplateDetail({
    requires: { integrations: [], repositories: [], secrets: [{ name: 'SENTRY_TOKEN', promptAtInstall: true }] },
  }),
  idempotencyKey: 'key-1',
  companyName: 'Acme',
  projects: [],
  selection: { projectId: null, projectName: null, inputs: [], resolutions: [] },
  plan: plan(),
  error: null,
  ...overrides,
});

describe('Templates/InstallPage', () => {
  it('installs a project template as a new project with the typed inputs, secrets and the confirmed plan', async () => {
    renderAuthedPage(<InstallPage />, { props: props() });

    expect(screen.getByText(/always installs as a new project/)).toBeInTheDocument();
    await userEvent.clear(screen.getByRole('textbox', { name: 'Default branch' }));
    await userEvent.type(screen.getByRole('textbox', { name: 'Default branch' }), 'trunk');
    await userEvent.type(screen.getByLabelText(/SENTRY_TOKEN/), 'tok-1');
    await userEvent.click(screen.getByRole('button', { name: 'Install' }));

    expect(router.post).toHaveBeenCalledWith(
      '/company/template_installs',
      expect.objectContaining({
        slug: 'dev-team-sdlc',
        inputs: { default_branch: 'trunk' },
        secrets: { SENTRY_TOKEN: 'tok-1' },
        digest: 'digest-1',
        idempotency_key: 'key-1',
      }),
      expect.anything(),
    );
  });

  it('holds the install until every conflict is resolved, and re-plans with the chosen resolution', async () => {
    renderAuthedPage(<InstallPage />, {
      props: props({
        template: buildTemplateDetail({ kind: 'workflow' }),
        projects: [{ id: 7, name: 'Payments' }],
        selection: { projectId: 7, projectName: null, inputs: [], resolutions: [] },
        plan: plan({
          target: 'existing_project',
          resolved: false,
          items: [{ section: 'agents', key: 'architect', name: 'architect', action: 'conflict', existingId: 3 }],
        }),
      }),
    });

    expect(screen.getByRole('button', { name: 'Resolve the conflicts first' })).toBeDisabled();
    expect(screen.getByText('A different architect already exists in this project.')).toBeInTheDocument();

    await userEvent.click(screen.getByText('Install as copy'));

    expect(router.get).toHaveBeenCalledWith(
      '/company/template_installs/new',
      expect.objectContaining({ project_id: 7, resolutions: { 'agents.architect': 'copy' } }),
      expect.anything(),
    );
  });

  it('explains why a template cannot be installed and offers no install button', () => {
    renderAuthedPage(<InstallPage />, { props: props({ plan: null, error: 'This template has been withdrawn' }) });

    expect(screen.getByText('This template has been withdrawn')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Install' })).not.toBeInTheDocument();
  });
});
