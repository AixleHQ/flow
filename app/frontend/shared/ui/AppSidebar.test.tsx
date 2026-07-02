import '@testing-library/jest-dom/vitest';

import { router } from '@inertiajs/react';
import { beforeEach, describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent } from 'test/renderPage';

import { AppSidebar } from './AppSidebar';
import type { SharedMembership, SharedProject } from './types';

const projects: SharedProject[] = [
  { id: 7, name: 'Aurora Platform', slug: 'aurora-platform', state: 'active' },
  { id: 8, name: 'Borealis Pipeline', slug: 'borealis-pipeline', state: 'active' },
];

describe('AppSidebar', () => {
  // The collapse toggle persists to localStorage, which jsdom keeps for the whole
  // file — clear it so a collapsing test cannot decide the next test's layout.
  beforeEach(() => localStorage.clear());

  it('renders company-level navigation with the user footer name and company name', () => {
    renderAuthedPage(<AppSidebar context="company" projects={projects} />, {
      props: {
        currentUser: {
          id: 1,
          email: 'nova@example.com',
          name: 'Nova Stargazer',
          state: 'active',
          position: null,
          preferredAgentLanguage: 'en',
          selectedAgents: [],
          onboardingState: 'completed',
          onboardingCompletedAt: null,
          defaultAgentCredentialId: null,
          defaultAgentRuntime: null,
          configuredAgents: [],
          agentCredentials: [],
          currentRole: 'admin',
          currentCompany: {
            id: 1,
            name: 'Globex Labs',
            emailDomain: 'example.com',
            logoUrl: null,
            primaryColor: null,
            secondaryColor: null,
          },
          memberships: [
            {
              id: 1,
              role: 'admin',
              state: 'active',
              company: {
                id: 1,
                name: 'Globex Labs',
                emailDomain: 'example.com',
                logoUrl: null,
                primaryColor: null,
                secondaryColor: null,
              },
            },
          ],
        },
      },
    });

    // Top-level company nav links are present.
    expect(screen.getByRole('link', { name: 'Projects' })).toHaveAttribute('href', '/company/projects');
    expect(screen.getByRole('link', { name: 'Members' })).toBeInTheDocument();

    // The workspace switcher shows "All Projects" (no current project) + company name.
    expect(screen.getByText('All Projects')).toBeInTheDocument();
    expect(screen.getByText('Globex Labs')).toBeInTheDocument();

    // User footer renders the current user's name.
    expect(screen.getByText('Nova Stargazer')).toBeInTheDocument();
  });

  it('hides admin-only links when the viewer is not an admin', () => {
    renderAuthedPage(<AppSidebar context="company" projects={projects} />, {
      props: { permissions: { isAdmin: false, canManageMembers: false, canManageProjects: false } },
    });

    // Non-admin keeps non-restricted items.
    expect(screen.getByRole('link', { name: 'Projects' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Members' })).toBeInTheDocument();

    // Admin-only items must not be rendered.
    expect(screen.queryByRole('link', { name: 'Assets' })).not.toBeInTheDocument();
  });

  it('shows admin-only links when the viewer is an admin', () => {
    renderAuthedPage(<AppSidebar context="company" projects={projects} />, {
      props: { permissions: { isAdmin: true, canManageMembers: true, canManageProjects: true } },
    });

    expect(screen.getByRole('link', { name: 'Assets' })).toBeInTheDocument();
  });

  it('renders project-scoped navigation with project-prefixed hrefs in project context', () => {
    renderAuthedPage(<AppSidebar projectId="7" context="project" projects={projects} currentProjectId="7" />);

    // Project nav items appear and link under the project id.
    expect(screen.getByRole('link', { name: 'Overview' })).toHaveAttribute('href', '/company/projects/7/overview');
    expect(screen.getByRole('link', { name: 'Tasks' })).toHaveAttribute('href', '/company/projects/7/board');
    expect(screen.getByRole('link', { name: 'Sessions' })).toBeInTheDocument();

    // The switcher reflects the current project's name as the workspace title.
    expect(screen.getByText('Aurora Platform')).toBeInTheDocument();
  });

  it('opens the workspace switcher and navigates to a selected project via router.visit', async () => {
    const user = userEvent.setup();
    renderAuthedPage(<AppSidebar context="company" projects={projects} />);

    // The switcher button shows "All Projects" while no project is current.
    await user.click(screen.getByRole('button', { name: /All Projects/ }));

    // Popover lists the available projects; click one to switch.
    const borealis = await screen.findByText('Borealis Pipeline');
    await user.click(borealis);

    expect(router.visit).toHaveBeenCalledWith('/company/projects/8');
  });

  it('sends "Build with AI" to the current project\'s builder in project context', async () => {
    const user = userEvent.setup();
    renderAuthedPage(<AppSidebar projectId="7" context="project" projects={projects} currentProjectId="7" />);

    expect(screen.getByText('AI Builder')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: /Build with AI/ }));

    expect(router.visit).toHaveBeenCalledWith('/company/projects/7/aixle_builder');
  });

  it('sends "Build with AI" to the project list when no project is selected', async () => {
    const user = userEvent.setup();
    renderAuthedPage(<AppSidebar context="company" projects={projects} />);

    await user.click(screen.getByRole('button', { name: /Build with AI/ }));

    // The builder only exists under a project, so company context must pick one
    // first — never the routeless /company/aixle_builder.
    expect(router.visit).toHaveBeenCalledWith('/company/projects');
    expect(router.visit).not.toHaveBeenCalledWith('/company/aixle_builder');
  });

  it('keeps the builder reachable from the collapsed sidebar', async () => {
    const user = userEvent.setup();
    renderAuthedPage(<AppSidebar projectId="7" context="project" projects={projects} currentProjectId="7" />);

    await user.click(screen.getByRole('button', { name: 'Collapse sidebar' }));

    // Collapsed, the banner shrinks to a single icon button labelled by its tooltip.
    await user.click(screen.getByRole('button', { name: 'AI Builder' }));

    expect(router.visit).toHaveBeenCalledWith('/company/projects/7/aixle_builder');
  });

  it('signs out through the user footer menu', async () => {
    const user = userEvent.setup();
    renderAuthedPage(<AppSidebar context="company" projects={[]} />, {
      props: { currentUser: { ...buildUser(), name: 'Cassia Vega' } },
    });

    await user.click(screen.getByRole('button', { name: /Cassia Vega/ }));
    const signOut = await screen.findByRole('menuitem', { name: 'Sign Out' });
    await user.click(signOut);

    expect(router.delete).toHaveBeenCalledWith('/logout');
  });

  it('toggles the collapsed state via the collapse button', async () => {
    const user = userEvent.setup();
    renderAuthedPage(<AppSidebar context="company" projects={projects} />);

    // Starts expanded -> button offers to collapse.
    const collapseBtn = screen.getByRole('button', { name: 'Collapse sidebar' });
    await user.click(collapseBtn);

    // After collapsing, the button flips to the expand affordance.
    expect(screen.getByRole('button', { name: 'Expand sidebar' })).toBeInTheDocument();
  });

  it('shows no company switcher for a single-membership user', () => {
    renderAuthedPage(<AppSidebar context="company" projects={projects} />, {
      props: { currentUser: buildUser() },
    });

    expect(screen.queryByRole('button', { name: 'Switch company' })).not.toBeInTheDocument();
  });

  it('switches company through the dropdown for a multi-membership user', async () => {
    // The collapse test above persists 'sidebar-collapsed'; the company
    // switcher only renders expanded.
    window.localStorage.clear();

    renderAuthedPage(<AppSidebar context="company" projects={projects} />, {
      props: { currentUser: { ...buildUser(), memberships: dualMemberships() } },
    });

    await userEvent.click(screen.getByRole('button', { name: 'Switch company' }));

    // Dropdown lists both companies; picking the other one posts the switch.
    await userEvent.click(await screen.findByText('Client Co'));
    expect(router.post).toHaveBeenCalledWith('/company/switch', { company_id: 2 });
  });

  it('does not post a switch when re-selecting the current company', async () => {
    window.localStorage.clear();

    renderAuthedPage(<AppSidebar context="company" projects={projects} />, {
      props: { currentUser: { ...buildUser(), memberships: dualMemberships() } },
    });

    await userEvent.click(screen.getByRole('button', { name: 'Switch company' }));
    // "Vega Corp" appears both as the switcher label and as a menu item — click the menu item.
    const items = await screen.findAllByText('Vega Corp');
    await userEvent.click(items[items.length - 1]);

    expect(router.post).not.toHaveBeenCalled();
  });
});

function dualMemberships(): SharedMembership[] {
  return [
    ...buildUser().memberships,
    {
      id: 2,
      role: 'viewer',
      state: 'active',
      company: {
        id: 2,
        name: 'Client Co',
        emailDomain: 'client-co.test',
        logoUrl: null,
        primaryColor: null,
        secondaryColor: null,
      },
    },
  ];
}

function buildUser() {
  return {
    id: 2,
    email: 'cassia@example.com',
    name: 'Cassia Vega',
    state: 'active',
    position: null,
    preferredAgentLanguage: 'en',
    selectedAgents: [],
    onboardingState: 'completed',
    onboardingCompletedAt: null,
    defaultAgentCredentialId: null,
    defaultAgentRuntime: null,
    configuredAgents: [],
    agentCredentials: [],
    currentRole: 'admin' as const,
    currentCompany: {
      id: 1,
      name: 'Vega Corp',
      emailDomain: 'example.com',
      logoUrl: null,
      primaryColor: null,
      secondaryColor: null,
    },
    memberships: [
      {
        id: 1,
        role: 'admin' as const,
        state: 'active',
        company: {
          id: 1,
          name: 'Vega Corp',
          emailDomain: 'example.com',
          logoUrl: null,
          primaryColor: null,
          secondaryColor: null,
        },
      },
    ],
  };
}
