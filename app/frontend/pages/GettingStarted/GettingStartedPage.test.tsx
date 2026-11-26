import '@testing-library/jest-dom/vitest';
import { router } from '@inertiajs/react';
import { describe, expect, it } from 'vitest';

import type { CurrentUser } from '@/types/generated';
import { buildSharedPermissions, buildSharedUser } from 'test/factories/sharedProps';
import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

import { ProductTourProvider } from 'shared/lib/productTour';
import {
  companyGettingStartedBuildWithAiPath,
  companyProjectsPath,
  mcpProfilePath,
  templatesPath,
} from 'shared/routes';

import GettingStartedPage from './GettingStartedPage';

const fakeHighlighter = { show: () => {}, clear: () => {} };

const renderGettingStarted = ({
  agents = ['claude_code'] as CurrentUser['configuredAgents'],
  canWrite = true,
  helloFlowAvailable = true,
} = {}) =>
  renderAuthedPage(
    <ProductTourProvider initialPage={null} highlighter={fakeHighlighter}>
      <GettingStartedPage />
    </ProductTourProvider>,
    {
      props: {
        currentUser: buildSharedUser({ configuredAgents: agents }),
        permissions: buildSharedPermissions({ canWrite }),
        helloFlowAvailable,
        helloFlowPath: '/templates/aixle/hello-flow',
        hasProjects: false,
      },
    },
  );

describe('GettingStarted/GettingStartedPage', () => {
  it('shows a member all four cards and starts tour A from the projects page', async () => {
    renderGettingStarted();

    expect(screen.getByRole('heading', { name: 'Connect your agents' })).toBeInTheDocument();
    expect(screen.getByText('Connected ✓')).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Discover community templates' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Browse templates' })).toHaveAttribute('href', templatesPath());
    expect(screen.getByRole('link', { name: 'Set up Personal MCP' })).toHaveAttribute('href', mcpProfilePath());

    await userEvent.click(screen.getByRole('button', { name: 'Take the product tour' }));

    expect(router.visit).toHaveBeenCalledWith(companyProjectsPath());
  });

  it('keeps the tour closed until an agent is connected', () => {
    renderGettingStarted({ agents: [] });

    expect(screen.queryByText('Connected ✓')).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Take the product tour' })).toBeDisabled();
    expect(screen.getByText('Connect an agent first')).toBeInTheDocument();
  });

  it('leaves the tour out where the starter template is not in the catalog', () => {
    renderGettingStarted({ helloFlowAvailable: false });

    expect(screen.queryByRole('button', { name: 'Take the product tour' })).not.toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Build your own' })).toBeInTheDocument();
  });

  it('builds with AI through the server, which picks or creates the project', async () => {
    renderGettingStarted();

    const buildYourOwn = screen.getByRole('region', { name: 'Build your own' });
    await userEvent.click(within(buildYourOwn).getByRole('button', { name: 'Build with AI' }));

    expect(router.post).toHaveBeenCalledWith(companyGettingStartedBuildWithAiPath());
  });

  it('gives a viewer only the tour, open without an agent or the starter template', async () => {
    renderGettingStarted({ agents: [], canWrite: false, helloFlowAvailable: false });

    expect(screen.queryByRole('heading', { name: 'Connect your agents' })).not.toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: 'Build your own' })).not.toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Take the product tour' }));

    expect(router.visit).toHaveBeenCalledWith(companyProjectsPath());
  });
});
