import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { buildTemplateDetail } from 'test/factories/template';
import { renderAuthedPage, renderPage, screen, userEvent } from 'test/renderPage';

import ShowPage from './ShowPage';

const installPath = '/company/template_installs/new?slug=dev-team-sdlc&version=3';

describe('Templates/ShowPage', () => {
  it('shows a guest what gets created and sends them to sign in to install', () => {
    renderPage(<ShowPage />, {
      props: { template: buildTemplateDetail(), installPath, signedIn: false, flash: {}, settings: {} },
    });

    expect(screen.getByRole('heading', { level: 1, name: 'Dev team SDLC' })).toBeInTheDocument();
    expect(screen.getByText('Tech Design')).toBeInTheDocument();
    expect(screen.getByText(/Tech design → Implement/)).toBeInTheDocument();
    expect(screen.getByText(/Installed inactive/)).toBeInTheDocument();
    expect(screen.getByText(/secrets only by name/)).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Sign in to install' })).toHaveAttribute('href', installPath);
  });

  it('lists every requirement with when it is asked for, and warns about third-party images', () => {
    renderAuthedPage(<ShowPage />, { props: { template: buildTemplateDetail(), installPath, signedIn: true } });

    expect(screen.getByText('github integration')).toBeInTheDocument();
    expect(screen.getByText('SENTRY_TOKEN')).toBeInTheDocument();
    expect(screen.getByText('Default branch')).toBeInTheDocument();
    expect(screen.getByText(/third-party container image/)).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Install' })).toBeInTheDocument();
  });

  it('renders the tables in the readme and the setup notes', async () => {
    renderAuthedPage(<ShowPage />, {
      props: {
        template: buildTemplateDetail({
          readme: '| Setting | Default |\n|---|---|\n| Integration branch | `develop` |',
          setup: '| Item | Set it when |\n|---|---|\n| `SPEC_PATH` | you keep a spec |',
        }),
        installPath,
        signedIn: true,
      },
    });

    await userEvent.click(screen.getByRole('tab', { name: 'Readme' }));
    expect(screen.getByRole('columnheader', { name: 'Setting' })).toBeInTheDocument();
    expect(screen.getByRole('cell', { name: 'Integration branch' })).toBeInTheDocument();

    await userEvent.click(screen.getByRole('tab', { name: 'Setup' }));
    expect(screen.getByRole('columnheader', { name: 'Set it when' })).toBeInTheDocument();
    expect(screen.getByRole('cell', { name: 'SPEC_PATH' })).toBeInTheDocument();
  });

  it('shows why a withdrawn template cannot be installed', () => {
    renderAuthedPage(<ShowPage />, {
      props: {
        template: buildTemplateDetail({ revoked: true, revocationReason: 'Ships a broken image.' }),
        installPath: null,
        signedIn: true,
      },
    });

    expect(screen.getByText('Ships a broken image.')).toBeInTheDocument();
    expect(screen.queryByRole('link', { name: 'Install' })).not.toBeInTheDocument();
  });
});
