import '@testing-library/jest-dom/vitest';

import { router } from '@inertiajs/react';
import { beforeEach, describe, expect, it } from 'vitest';

import { renderAuthedPage, screen, userEvent, within } from 'test/renderPage';

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
    // Sessions and runs are one entry, pointing at the unified list.
    expect(screen.getByRole('link', { name: 'Sessions & Runs' })).toHaveAttribute(
      'href',
      '/company/projects/7/sessions',
    );
    expect(screen.queryByRole('link', { name: 'Runs' })).not.toBeInTheDocument();

    // The switcher reflects the current project's name as the workspace title.
    expect(screen.getByText('Aurora Platform')).toBeInTheDocument();
  });

  // The switcher's project rows are real Inertia <Link>s; left alone, a click would trigger
  // the real Router.visit (which has no live page context under jsdom and throws). A
  // capture-phase preventDefault makes Inertia's shouldIntercept() bail out before visiting,
  // while React's synthetic onClick still fires.
  function suppressHardNavigation() {
    const handler = (e: Event) => e.preventDefault();
    document.addEventListener('click', handler, true);
    return () => document.removeEventListener('click', handler, true);
  }

  async function openSwitcher(user: ReturnType<typeof userEvent.setup>) {
    // The switcher button shows "All Projects" while no project is current.
    await user.click(screen.getByRole('button', { name: /All Projects/ }));
    return screen.findByRole('link', { name: /Borealis Pipeline/ });
  }

  // Rendering each project as a link is what buys the browser-native affordances the
  // switcher needs: Cmd/Ctrl+click into a new tab and a right-click "Open in new
  // tab/window" context menu. Both are the browser's job once there is an href.
  it('opens the workspace switcher and lists each project as a link to that project', async () => {
    const user = userEvent.setup();
    renderAuthedPage(<AppSidebar context="company" projects={projects} />);

    const borealis = await openSwitcher(user);

    expect(borealis).toHaveAttribute('href', '/company/projects/8');
    expect(screen.getByRole('link', { name: /Aurora Platform/ })).toHaveAttribute('href', '/company/projects/7');
  });

  it('marks the current project link as the active page in the switcher', async () => {
    const user = userEvent.setup();
    renderAuthedPage(<AppSidebar projectId="7" context="project" projects={projects} currentProjectId="7" />);

    await user.click(screen.getByRole('button', { name: /Aurora Platform/ }));

    expect(await screen.findByRole('link', { name: /Aurora Platform/ })).toHaveAttribute('aria-current', 'page');
    expect(screen.getByRole('link', { name: /Borealis Pipeline/ })).not.toHaveAttribute('aria-current');
  });

  it('closes the switcher on a plain click, which navigates in the same tab', async () => {
    const restore = suppressHardNavigation();
    const user = userEvent.setup();
    renderAuthedPage(<AppSidebar context="company" projects={projects} />);

    const borealis = await openSwitcher(user);
    await user.click(borealis);

    expect(screen.queryByRole('link', { name: /Borealis Pipeline/ })).not.toBeInTheDocument();
    restore();
  });

  // A modifier-click opens the project in another tab and leaves this one where it was, so
  // dismissing the popover would hide a switcher that never switched.
  it('keeps the switcher open on a modifier-click, letting the browser open a new tab', async () => {
    const restore = suppressHardNavigation();
    const user = userEvent.setup();
    renderAuthedPage(<AppSidebar context="company" projects={projects} />);

    const borealis = await openSwitcher(user);
    await user.keyboard('{Meta>}');
    await user.click(borealis);
    await user.keyboard('{/Meta}');

    expect(screen.getByRole('link', { name: /Borealis Pipeline/ })).toBeInTheDocument();
    restore();
  });

  it('sends "Build with AI" to the current project\'s builder in project context', async () => {
    const user = userEvent.setup();
    renderAuthedPage(<AppSidebar projectId="7" context="project" projects={projects} currentProjectId="7" />);

    expect(screen.getByText('Tasks, boards, and workflows — from one prompt.')).toBeInTheDocument();
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

  it('collapses and re-expands a nav group, hiding and showing its items', async () => {
    const user = userEvent.setup();
    renderAuthedPage(<AppSidebar projectId="7" context="project" projects={projects} currentProjectId="7" />);

    // All groups are expanded by default.
    expect(screen.getByRole('link', { name: 'Tasks' })).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: 'Work' }));
    expect(screen.queryByRole('link', { name: 'Tasks' })).not.toBeInTheDocument();
    // Other groups are unaffected.
    expect(screen.getByRole('link', { name: 'Agents' })).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: 'Work' }));
    expect(screen.getByRole('link', { name: 'Tasks' })).toBeInTheDocument();
  });

  it('persists a collapsed nav group across remounts', async () => {
    const user = userEvent.setup();
    const { unmount } = renderAuthedPage(
      <AppSidebar projectId="7" context="project" projects={projects} currentProjectId="7" />,
    );

    await user.click(screen.getByRole('button', { name: 'Work' }));
    expect(screen.queryByRole('link', { name: 'Tasks' })).not.toBeInTheDocument();
    unmount();

    renderAuthedPage(<AppSidebar projectId="7" context="project" projects={projects} currentProjectId="7" />);
    expect(screen.queryByRole('link', { name: 'Tasks' })).not.toBeInTheDocument();
  });

  it('shows every item in the icon rail even when its group is collapsed', async () => {
    const user = userEvent.setup();
    renderAuthedPage(<AppSidebar projectId="7" context="project" projects={projects} currentProjectId="7" />);

    await user.click(screen.getByRole('button', { name: 'Work' }));
    expect(screen.queryByRole('link', { name: 'Tasks' })).not.toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: 'Collapse sidebar' }));
    expect(screen.getByRole('link', { name: 'Tasks' })).toBeInTheDocument();
  });

  // The company switcher is a Slack-style rail left of the sidebar. A
  // single-company user must see no tenancy chrome at all.
  it('shows no company rail for a single-membership user', () => {
    renderAuthedPage(<AppSidebar context="company" projects={projects} />, {
      props: { currentUser: buildUser() },
    });

    expect(screen.queryByRole('navigation', { name: 'Switch company' })).not.toBeInTheDocument();
  });

  it('renders one rail tile per company, marking the current one', () => {
    renderAuthedPage(<AppSidebar context="company" projects={projects} />, {
      props: { currentUser: { ...buildUser(), memberships: dualMemberships() } },
    });

    const rail = screen.getByRole('navigation', { name: 'Switch company' });
    expect(within(rail).getByRole('button', { name: /Vega Corp/ })).toHaveAttribute('aria-current', 'true');
    expect(within(rail).getByRole('button', { name: /Client Co/ })).not.toHaveAttribute('aria-current');
  });

  it('switches company from the rail for a multi-membership user', async () => {
    renderAuthedPage(<AppSidebar context="company" projects={projects} />, {
      props: { currentUser: { ...buildUser(), memberships: dualMemberships() } },
    });

    const rail = screen.getByRole('navigation', { name: 'Switch company' });
    await userEvent.click(within(rail).getByRole('button', { name: /Client Co/ }));

    expect(router.post).toHaveBeenCalledWith('/company/switch', { company_id: 2 });
  });

  it('does not post a switch when re-selecting the current company', async () => {
    renderAuthedPage(<AppSidebar context="company" projects={projects} />, {
      props: { currentUser: { ...buildUser(), memberships: dualMemberships() } },
    });

    // Scope to the rail: the sidebar's workspace button also carries the
    // company name as its sub-label.
    const rail = screen.getByRole('navigation', { name: 'Switch company' });
    await userEvent.click(within(rail).getByRole('button', { name: /Vega Corp/ }));

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
