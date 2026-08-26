import { Link, router, usePage } from '@inertiajs/react';
import { Drawer, Menu, Popover, ScrollArea, Tooltip, UnstyledButton } from '@mantine/core';
import { useDisclosure, useMediaQuery } from '@mantine/hooks';
import {
  IconAlertTriangle,
  IconChartBar,
  IconCheck,
  IconCheckbox,
  IconChevronDown,
  IconFiles,
  IconGitBranch,
  IconGitMerge,
  IconKey,
  IconLayoutDashboard,
  IconLayoutGrid,
  IconLayoutSidebar,
  IconLogout,
  IconMenu2,
  IconPlug,
  IconPlugConnected,
  IconRobot,
  IconSettings,
  IconSparkles,
  IconTerminal2,
  IconTool,
  IconUser,
  IconUsers,
  IconWand,
} from '@tabler/icons-react';
import { Fragment, useCallback, useMemo, useState } from 'react';

import { CreateProjectModal } from 'pages/Projects/CreateProjectModal';
import { getInitials } from 'shared/lib/getInitials';
import {
  companyAssetsPath,
  companyMembersPath,
  companyProjectAgentsPath,
  companyProjectAixleBuilderPath,
  companyProjectAnalyticsPath,
  companyProjectAssetsPath,
  companyProjectBoardPath,
  companyProjectConfigItemsPath,
  companyProjectIntegrationsPath,
  companyProjectMCPServersPath,
  companyProjectMembersPath,
  companyProjectOverviewIndexPath,
  companyProjectPath,
  companyProjectRepositoriesPath,
  companyProjectSessionsPath,
  companyProjectSettingsPath,
  companyProjectSkillsPath,
  companyProjectToolsPath,
  companyProjectWorkflowsPath,
  companyProjectsPath,
  companySessionsPath,
  companySwitchPath,
  companyWorkflowCatalogIndexPath,
  profilePath,
} from 'shared/routes';

import classes from './AppSidebar.module.css';
import { ColorSchemeToggle } from './ColorSchemeToggle';
import type { SharedMembership, SharedPermissions, SharedProject, SharedProps } from './types';

const SIDEBAR_WIDTH = 220;
const SIDEBAR_COLLAPSED_WIDTH = 60;
const STORAGE_KEY = 'sidebar-collapsed';
const GROUPS_STORAGE_KEY = 'sidebar-collapsed-groups';

const readCollapsedGroups = (): Set<string> => {
  try {
    const raw = localStorage.getItem(GROUPS_STORAGE_KEY);
    return raw ? new Set(JSON.parse(raw) as string[]) : new Set();
  } catch {
    return new Set();
  }
};

const writeCollapsedGroups = (groups: Set<string>) => {
  try {
    localStorage.setItem(GROUPS_STORAGE_KEY, JSON.stringify([...groups]));
  } catch {
    // localStorage unavailable (private browsing, quota exceeded)
  }
};

// True for the clicks the browser handles itself on a link — Cmd/Ctrl+click (new tab),
// Shift+click (new window), Alt+click (download) and anything but the primary button.
const isModifiedClick = (event: React.MouseEvent): boolean =>
  event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button !== 0;

const handleLogout = () => router.delete('/logout');

// ─── Nav item definition ──────────────────────────────────────────────────────

interface NavItem {
  label: string;
  icon: React.ReactNode;
  path: string;
  adminOnly?: boolean;
}

interface NavGroup {
  label?: string;
  items: NavItem[];
}

// ─── Project-level nav ────────────────────────────────────────────────────────

const buildProjectNavGroups = (projectId: string): NavGroup[] => [
  {
    items: [
      { label: 'Overview', icon: <IconLayoutDashboard size={18} />, path: companyProjectOverviewIndexPath(projectId) },
    ],
  },
  {
    label: 'Work',
    items: [
      { label: 'Tasks', icon: <IconCheckbox size={18} />, path: companyProjectBoardPath(projectId) },
      { label: 'Workflows', icon: <IconGitMerge size={18} />, path: companyProjectWorkflowsPath(projectId) },
      // One entry: agent sessions and workflow runs share a single list.
      { label: 'Sessions & Runs', icon: <IconTerminal2 size={18} />, path: companyProjectSessionsPath(projectId) },
      { label: 'Assets', icon: <IconFiles size={18} />, path: companyProjectAssetsPath(projectId) },
    ],
  },
  {
    label: 'Resources',
    items: [
      { label: 'Agents', icon: <IconRobot size={18} />, path: companyProjectAgentsPath(projectId) },
      { label: 'Wrappers', icon: <IconTool size={18} />, path: companyProjectToolsPath(projectId) },
      { label: 'Skills', icon: <IconSparkles size={18} />, path: companyProjectSkillsPath(projectId) },
      { label: 'Connectors', icon: <IconPlugConnected size={18} />, path: companyProjectMCPServersPath(projectId) },
      { label: 'Repositories', icon: <IconGitBranch size={18} />, path: companyProjectRepositoriesPath(projectId) },
      { label: 'Integrations', icon: <IconPlug size={18} />, path: companyProjectIntegrationsPath(projectId) },
    ],
  },
  {
    label: 'Admin',
    items: [
      {
        label: 'Secrets & Variables',
        icon: <IconKey size={18} />,
        path: companyProjectConfigItemsPath(projectId),
      },
      { label: 'Members', icon: <IconUsers size={18} />, path: companyProjectMembersPath(projectId) },
      { label: 'Analytics', icon: <IconChartBar size={18} />, path: companyProjectAnalyticsPath(projectId) },
      {
        label: 'Settings',
        icon: <IconSettings size={18} />,
        path: companyProjectSettingsPath(projectId),
      },
    ],
  },
];

// ─── Company-level nav ────────────────────────────────────────────────────────

const companyNavGroups: NavGroup[] = [
  {
    items: [{ label: 'Projects', icon: <IconLayoutGrid size={18} />, path: companyProjectsPath() }],
  },
  {
    label: 'Monitoring',
    items: [
      { label: 'Analytics', icon: <IconChartBar size={18} />, path: '/company/analytics', adminOnly: true }, // TODO: use companyAnalyticsPath() when route helper is available
      { label: 'Sessions', icon: <IconTerminal2 size={18} />, path: companySessionsPath(), adminOnly: true },
    ],
  },
  {
    label: 'Library',
    items: [{ label: 'Workflow Catalog', icon: <IconGitMerge size={18} />, path: companyWorkflowCatalogIndexPath() }],
  },
  {
    label: 'Admin',
    items: [
      { label: 'Assets', icon: <IconFiles size={18} />, path: companyAssetsPath(), adminOnly: true },
      { label: 'Members', icon: <IconUsers size={18} />, path: companyMembersPath() },
    ],
  },
];

// ─── Company rail (Slack-style workspace switcher) ───────────────────────────
// A narrow strip left of the sidebar, rendered ONLY for people who belong to
// more than one company — a single-company user should never see tenancy chrome
// at all. Each company is one square; the current one is marked. Switching is a
// full Inertia visit, so every shared prop (projects, permissions, current user)
// re-resolves server-side for the new company.

function CompanyRail({
  memberships,
  currentCompanyId,
}: {
  memberships: SharedMembership[];
  currentCompanyId: number | null;
}) {
  const switchTo = (companyId: number) => {
    if (companyId === currentCompanyId) return;
    router.post(companySwitchPath(), { company_id: companyId });
  };

  return (
    <div className={classes.rail} role="navigation" aria-label="Switch company">
      {memberships.map((membership) => {
        const isCurrent = membership.company.id === currentCompanyId;
        const role = MEMBERSHIP_ROLE_LABELS[membership.role] ?? membership.role;

        return (
          <Tooltip key={membership.id} label={`${membership.company.name} — ${role}`} position="right" withArrow>
            <UnstyledButton
              onClick={() => switchTo(membership.company.id)}
              className={`${classes.railItem} ${isCurrent ? classes.railItemActive : ''}`}
              aria-label={`${membership.company.name} (${role})`}
              aria-current={isCurrent ? 'true' : undefined}
            >
              <span className={classes.railTile}>{getInitials(membership.company.name)}</span>
            </UnstyledButton>
          </Tooltip>
        );
      })}
    </div>
  );
}

// ─── "Connect an agent" nudge ────────────────────────────────────────────────
// Onboarding skips the agent step for a user who is a viewer in every company.
// If they are later given a role that can run things, onboarding never re-runs,
// so without this they just find empty agent pickers with no explanation.

function AgentSetupNudge({ collapsed }: { collapsed: boolean }) {
  const label = 'Connect an agent to start running workflows';

  if (collapsed) {
    return (
      <Tooltip label={label} position="right" withArrow>
        <UnstyledButton
          component={Link}
          href={profilePath()}
          aria-label={label}
          className={classes.agentNudgeCollapsed}
        >
          <IconAlertTriangle size={16} />
        </UnstyledButton>
      </Tooltip>
    );
  }

  return (
    <UnstyledButton component={Link} href={profilePath()} className={classes.agentNudge}>
      <IconAlertTriangle size={15} className={classes.agentNudgeIcon} />
      <span className={classes.agentNudgeText}>{label}</span>
    </UnstyledButton>
  );
}

// ─── AI Builder sidebar banner (AC11) ────────────────────────────────────────

interface AiBannerProps {
  collapsed: boolean;
  projectId?: string | null;
}

function AiBanner({ collapsed, projectId }: AiBannerProps) {
  // The builder is project-scoped (its sessions, assets and tools all hang off a
  // project), so there is no company-level builder route to send a project-less
  // visitor to — company context routes to the project list to pick one first.
  const handleClick = () => {
    router.visit(projectId ? companyProjectAixleBuilderPath(projectId) : companyProjectsPath());
  };

  if (collapsed) {
    return (
      <div className={classes.aiBannerCollapsed}>
        <Tooltip label="AI Builder" position="right" withArrow>
          <UnstyledButton onClick={handleClick} aria-label="AI Builder" className={classes.aiBannerIcon}>
            <IconWand size={16} />
          </UnstyledButton>
        </Tooltip>
      </div>
    );
  }

  return (
    <div className={classes.aiBanner}>
      <div className={classes.aiBannerCard}>
        <button type="button" onClick={handleClick} className={classes.aiBannerCta}>
          <IconSparkles size={13} />
          <span>Build with AI</span>
        </button>
        <div className={classes.aiBannerCap}>Tasks, boards, and workflows — from one prompt.</div>
      </div>
    </div>
  );
}

// ─── SidebarNav ───────────────────────────────────────────────────────────────

interface SidebarNavProps {
  groups: NavGroup[];
  collapsed: boolean;
  isAdmin: boolean;
  collapsedGroups: Set<string>;
  toggleGroup: (label: string) => void;
  onNavigate?: () => void;
}

function SidebarNav({ groups, collapsed, isAdmin, collapsedGroups, toggleGroup, onNavigate }: SidebarNavProps) {
  // Read the path from Inertia, not `window.location`. AuthLayout is a
  // persistent layout for project pages, so the sidebar can survive a visit
  // without re-rendering — reading `window.location.pathname` at render time
  // left the active highlight pointing at the previous page.
  const currentPath = usePage().url.split('?')[0];

  return (
    <>
      {groups.map((group, groupIdx) => {
        const visibleItems = group.items.filter((item) => !item.adminOnly || isAdmin);
        if (visibleItems.length === 0) return null;

        // In the icon rail, groups always show every icon — there's no room for a
        // label to click, so per-group collapse only applies to the expanded sidebar.
        const groupCollapsed = !collapsed && group.label !== undefined && collapsedGroups.has(group.label);

        return (
          <Fragment key={groupIdx}>
            {group.label && (
              <button
                type="button"
                onClick={() => toggleGroup(group.label as string)}
                aria-expanded={!groupCollapsed}
                className={`${classes.navGroupLabel} ${collapsed ? classes.navGroupLabelCollapsed : ''}`}
              >
                <span>{group.label}</span>
                <IconChevronDown
                  size={12}
                  className={`${classes.groupCaret} ${groupCollapsed ? classes.groupCaretCollapsed : ''}`}
                />
              </button>
            )}
            {!groupCollapsed &&
              visibleItems.map((item, itemIdx) => {
                const isActive = currentPath === item.path || currentPath.startsWith(item.path + '/');
                const isOverview = groupIdx === 0 && itemIdx === 0 && !group.label;

                if (collapsed) {
                  const iconEl = <span className={classes.navItemIconCollapsed}>{item.icon}</span>;
                  return (
                    <Tooltip key={item.path} label={item.label} position="right" withArrow>
                      <Link
                        href={item.path}
                        onClick={onNavigate}
                        aria-label={item.label}
                        aria-current={isActive ? 'page' : undefined}
                        className={[
                          isOverview ? classes.navOverview : classes.navItem,
                          isOverview ? classes.navOverviewCollapsed : classes.navItemCollapsed,
                          isActive ? (isOverview ? classes.navOverviewActive : classes.navItemActive) : '',
                        ].join(' ')}
                      >
                        {iconEl}
                      </Link>
                    </Tooltip>
                  );
                }

                return (
                  <Link
                    key={item.path}
                    href={item.path}
                    onClick={onNavigate}
                    aria-current={isActive ? 'page' : undefined}
                    className={[
                      isOverview ? classes.navOverview : classes.navItem,
                      isActive ? (isOverview ? classes.navOverviewActive : classes.navItemActive) : '',
                    ].join(' ')}
                  >
                    <span className={classes.navItemIcon}>{item.icon}</span>
                    <span className={classes.navItemLabel}>{item.label}</span>
                  </Link>
                );
              })}
          </Fragment>
        );
      })}
    </>
  );
}

// ─── SidebarWorkspaceSwitcher ─────────────────────────────────────────────────

const MEMBERSHIP_ROLE_LABELS: Record<SharedMembership['role'], string> = {
  admin: 'Admin',
  employee: 'Employee',
  viewer: 'Viewer',
};

interface SidebarWorkspaceSwitcherProps {
  collapsed: boolean;
  projects: SharedProject[];
  currentProjectId: string | null;
  companyName: string;
  context: 'project' | 'company';
  onExpand: () => void;
}

function SidebarWorkspaceSwitcher({
  collapsed,
  projects,
  currentProjectId,
  companyName,
  context,
  onExpand,
}: SidebarWorkspaceSwitcherProps) {
  const [popoverOpen, setPopoverOpen] = useState(false);
  const [search, setSearch] = useState('');
  const [createModalOpened, setCreateModalOpened] = useState(false);

  const currentProject = currentProjectId ? (projects.find((p) => String(p.id) === currentProjectId) ?? null) : null;

  const filteredProjects = useMemo(
    () =>
      search.trim()
        ? projects.filter((p) => p.name.toLocaleLowerCase().includes(search.toLocaleLowerCase()))
        : projects,
    [search, projects],
  );

  const handleSwitcherClick = () => {
    if (collapsed) {
      onExpand();
    }
    setPopoverOpen((v) => !v);
  };

  // Project rows are real links, so the browser owns modifier-click (Cmd/Ctrl+click opens a
  // new tab) and the right-click "Open in new tab/window" menu; Inertia's Link leaves both
  // alone and only intercepts a plain left click for the same-tab visit. A modifier-click
  // leaves this tab where it is, so the popover stays open — only a plain click closes it.
  const handleProjectClick = (event: React.MouseEvent) => {
    if (isModifiedClick(event)) return;
    setPopoverOpen(false);
  };

  const handleAllProjectsClick = () => {
    setPopoverOpen(false);
    router.visit(companyProjectsPath());
  };

  const handleNewProject = () => {
    setPopoverOpen(false);
    setCreateModalOpened(true);
  };

  const displayName = currentProject ? currentProject.name : 'All Projects';
  const isCompanyContext = context === 'company';

  return (
    <div className={`${classes.swArea} ${collapsed ? classes.swAreaCollapsed : ''}`}>
      <Popover
        opened={popoverOpen && !collapsed}
        onChange={setPopoverOpen}
        onClose={() => setPopoverOpen(false)}
        closeOnClickOutside
        width="target"
        shadow="md"
        withArrow={false}
        offset={4}
        transitionProps={{ transition: 'pop', duration: 160 }}
      >
        <Popover.Target>
          <UnstyledButton
            className={[
              classes.swBtn,
              collapsed ? classes.swBtnCollapsed : '',
              popoverOpen ? classes.swBtnOpen : '',
            ].join(' ')}
            onClick={handleSwitcherClick}
          >
            {isCompanyContext ? (
              <div className={`${classes.swIco} ${classes.swIcoCompany} ${collapsed ? classes.swIcoCollapsed : ''}`}>
                <IconLayoutGrid size={14} style={{ color: 'var(--app-text-secondary)' }} />
              </div>
            ) : (
              <div className={`${classes.swIco} ${collapsed ? classes.swIcoCollapsed : ''}`}>
                <span className={classes.swIcoLetter}>{((currentProject?.name ?? 'P')[0] ?? 'P').toUpperCase()}</span>
              </div>
            )}
            <div className={`${classes.swText} ${collapsed ? classes.swTextCollapsed : ''}`}>
              <div className={classes.swName}>{displayName}</div>
              {/* Company identity now lives in the left rail (CompanyRail). */}
              <div className={classes.swSub}>{companyName}</div>
            </div>
            <IconChevronDown
              size={12}
              className={`${classes.swCaret} ${collapsed ? classes.swCaretCollapsed : ''} ${popoverOpen ? classes.swCaretOpen : ''}`}
            />
          </UnstyledButton>
        </Popover.Target>

        <Popover.Dropdown className={classes.swDropdown}>
          <div className={classes.swSearch}>
            <input
              className={classes.swSearchInput}
              type="text"
              placeholder="Search..."
              aria-label="Search projects"
              value={search}
              onChange={(e) => setSearch(e.currentTarget.value)}
            />
          </div>

          <div className={classes.swSection}>
            <span className={classes.dpLabel}>PROJECTS</span>
            {filteredProjects.map((project) => {
              const isActive = String(project.id) === currentProjectId;
              return (
                <UnstyledButton
                  key={project.id}
                  component={Link}
                  href={companyProjectPath(String(project.id))}
                  aria-current={isActive ? 'page' : undefined}
                  className={`${classes.dpItem} ${isActive ? classes.dpItemActive : ''}`}
                  onClick={handleProjectClick}
                >
                  <div className={classes.dpIco}>
                    <span className={classes.dpIcoLetter}>{(project.name?.[0] ?? 'P').toUpperCase()}</span>
                  </div>
                  <span className={classes.dpName}>{project.name}</span>
                  {isActive && <IconCheck size={12} className={classes.dpCheck} />}
                </UnstyledButton>
              );
            })}
          </div>

          <div className={classes.swSection}>
            <span className={classes.dpLabel}>ADMIN</span>
            <UnstyledButton
              className={`${classes.dpItem} ${isCompanyContext ? classes.dpItemActiveCo : ''}`}
              onClick={handleAllProjectsClick}
            >
              <div className={`${classes.dpIco} ${classes.dpIcoCompany}`}>
                <IconLayoutGrid size={14} style={{ color: 'var(--app-text-secondary)' }} />
              </div>
              <span className={classes.dpName}>All Projects</span>
              {isCompanyContext && <IconCheck size={12} className={classes.dpCheck} />}
            </UnstyledButton>
          </div>

          <div className={classes.dpFooter}>
            <button
              type="button"
              className={classes.dpNewProject}
              onClick={handleNewProject}
              aria-label="Create new project"
            >
              + New project
            </button>
          </div>
        </Popover.Dropdown>
      </Popover>

      <CreateProjectModal opened={createModalOpened} onClose={() => setCreateModalOpened(false)} />
    </div>
  );
}

// ─── SidebarUserFooter ────────────────────────────────────────────────────────

interface SidebarUserFooterProps {
  userName: string;
  collapsed: boolean;
}

function SidebarUserFooter({ userName, collapsed }: SidebarUserFooterProps) {
  return (
    <div className={`${classes.navFoot} ${collapsed ? classes.navFootCollapsed : ''}`}>
      <Menu position="top-start" width={200} shadow="md">
        <Menu.Target>
          <UnstyledButton className={`${classes.userRow} ${collapsed ? classes.userRowCollapsed : ''}`}>
            <Tooltip label={userName} position="right" withArrow disabled={!collapsed}>
              <div className={`${classes.userAvatar} ${collapsed ? classes.userAvatarCollapsed : ''}`}>
                <span className={classes.userAvatarInitials}>{getInitials(userName)}</span>
              </div>
            </Tooltip>
            <span className={`${classes.userName} ${collapsed ? classes.userNameCollapsed : ''}`}>{userName}</span>
            <IconChevronDown
              size={12}
              className={`${classes.userCaret} ${collapsed ? classes.userCaretCollapsed : ''}`}
            />
          </UnstyledButton>
        </Menu.Target>
        <Menu.Dropdown>
          <Menu.Item component={Link} href="/profile" leftSection={<IconUser size={16} />}>
            My Profile
          </Menu.Item>
          <Menu.Divider />
          <Menu.Item leftSection={<IconLogout size={16} />} onClick={handleLogout}>
            Sign Out
          </Menu.Item>
        </Menu.Dropdown>
      </Menu>
    </div>
  );
}

// ─── AppSidebar ───────────────────────────────────────────────────────────────

interface AppSidebarProps {
  projectId?: string | null;
  currentTab?: string;
  context?: 'project' | 'company';
  projects?: SharedProject[];
  currentProjectId?: string | null;
  permissions?: SharedPermissions;
}

function SidebarContent({
  projectId,
  context,
  projects,
  currentProjectId,
  permissions,
  collapsed,
  onExpand,
  toggleCollapsed,
  onNavigate,
}: {
  projectId?: string | null;
  context: 'project' | 'company';
  projects: SharedProject[];
  currentProjectId: string | null;
  permissions?: SharedPermissions;
  collapsed: boolean;
  onExpand: () => void;
  toggleCollapsed: () => void;
  onNavigate?: () => void;
}) {
  const { currentUser } = usePage<SharedProps>().props;
  const isAdmin = permissions?.isAdmin ?? false;
  const companyName = currentUser?.currentCompany?.name ?? '';

  const navGroups = context === 'project' && projectId ? buildProjectNavGroups(projectId) : companyNavGroups;

  const [collapsedGroups, setCollapsedGroups] = useState<Set<string>>(() => readCollapsedGroups());
  const toggleGroup = useCallback((label: string) => {
    setCollapsedGroups((prev) => {
      const next = new Set(prev);
      if (next.has(label)) {
        next.delete(label);
      } else {
        next.add(label);
      }
      writeCollapsedGroups(next);
      return next;
    });
  }, []);

  return (
    <>
      <SidebarWorkspaceSwitcher
        collapsed={collapsed}
        projects={projects}
        currentProjectId={currentProjectId}
        companyName={companyName}
        context={context}
        onExpand={onExpand}
      />

      <ScrollArea className={classes.scrollArea} type="never">
        <SidebarNav
          groups={navGroups}
          collapsed={collapsed}
          isAdmin={isAdmin}
          collapsedGroups={collapsedGroups}
          toggleGroup={toggleGroup}
          onNavigate={onNavigate}
        />
      </ScrollArea>

      {currentUser?.needsAgentSetup && <AgentSetupNudge collapsed={collapsed} />}

      <AiBanner collapsed={collapsed} projectId={projectId} />

      <div className={`${classes.collapseRow} ${collapsed ? classes.collapseRowCollapsed : ''}`}>
        <ColorSchemeToggle className={classes.collapseBtn} tooltipPosition={collapsed ? 'right' : 'top'} />
        <UnstyledButton
          onClick={toggleCollapsed}
          className={classes.collapseBtn}
          aria-label={collapsed ? 'Expand sidebar' : 'Collapse sidebar'}
        >
          <IconLayoutSidebar size={16} />
        </UnstyledButton>
      </div>

      {currentUser && <SidebarUserFooter userName={currentUser.name} collapsed={collapsed} />}
    </>
  );
}

export const AppSidebar = ({
  projectId,
  context: propContext,
  projects: propProjects,
  currentProjectId: propCurrentProjectId,
  permissions: propPermissions,
}: AppSidebarProps) => {
  const { projects: pageProjects = [], permissions: pagePermissions, currentUser } = usePage<SharedProps>().props;
  // The rail is the only tenancy chrome a single-company user must never see.
  const memberships = currentUser?.memberships ?? [];
  const currentCompanyId = currentUser?.currentCompany?.id ?? null;
  const currentCompanyName = currentUser?.currentCompany?.name ?? '';
  const multiCompany = memberships.length > 1;

  const projects = propProjects ?? pageProjects;
  const permissions = propPermissions ?? pagePermissions;
  const context = propContext ?? (projectId ? 'project' : 'company');
  const currentProjectId = propCurrentProjectId ?? projectId ?? null;

  const [collapsed, setCollapsed] = useState(() => {
    try {
      return localStorage.getItem(STORAGE_KEY) === 'true';
    } catch {
      return false;
    }
  });
  const isMobile = useMediaQuery('(max-width: 768px)');
  const [drawerOpened, { open: openDrawer, close: closeDrawer }] = useDisclosure(false);
  const width = collapsed ? SIDEBAR_COLLAPSED_WIDTH : SIDEBAR_WIDTH;

  const toggleCollapsed = useCallback(() => {
    setCollapsed((prev) => {
      const next = !prev;
      try {
        localStorage.setItem(STORAGE_KEY, String(next));
      } catch {
        // localStorage unavailable (private browsing, quota exceeded)
      }
      return next;
    });
  }, []);

  const onExpand = useCallback(() => {
    setCollapsed(false);
    try {
      localStorage.setItem(STORAGE_KEY, 'false');
    } catch {
      // localStorage unavailable
    }
  }, []);

  if (isMobile) {
    return (
      <>
        <div className={classes.mobileBar}>
          <UnstyledButton onClick={openDrawer} className={classes.mobileToggle} aria-label="Open navigation">
            <IconMenu2 size={20} />
          </UnstyledButton>
          <span className={classes.mobileBarTitle}>{currentCompanyName}</span>
        </div>
        <Drawer
          opened={drawerOpened}
          onClose={closeDrawer}
          size={SIDEBAR_WIDTH}
          padding={0}
          withCloseButton={false}
          styles={{
            body: {
              padding: 0,
              height: '100%',
              backgroundColor: 'var(--app-bg-paper)',
              display: 'flex',
              flexDirection: 'column',
            },
          }}
        >
          <SidebarContent
            projectId={projectId}
            context={context}
            projects={projects}
            currentProjectId={currentProjectId}
            permissions={permissions}
            collapsed={false}
            onExpand={() => {}}
            toggleCollapsed={() => {}}
            onNavigate={closeDrawer}
          />
        </Drawer>
      </>
    );
  }

  return (
    <div className={classes.shell}>
      {multiCompany && <CompanyRail memberships={memberships} currentCompanyId={currentCompanyId} />}
      <nav
        className={`${classes.root} ${collapsed ? classes.rootCollapsed : ''}`}
        style={{ width, minWidth: width }}
        aria-label={context === 'project' ? 'Project navigation' : 'Workspace navigation'}
      >
        <SidebarContent
          projectId={projectId}
          context={context}
          projects={projects}
          currentProjectId={currentProjectId}
          permissions={permissions}
          collapsed={collapsed}
          onExpand={onExpand}
          toggleCollapsed={toggleCollapsed}
        />
      </nav>
    </div>
  );
};
