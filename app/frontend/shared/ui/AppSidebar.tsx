import { Link, router, usePage } from '@inertiajs/react';
import { Drawer, Menu, Popover, ScrollArea, Tooltip, UnstyledButton } from '@mantine/core';
import { useDisclosure, useMediaQuery } from '@mantine/hooks';
import {
  IconArrowsExchange,
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
  IconPlayerPlay,
  IconPlugConnected,
  IconRobot,
  IconSettings,
  IconSparkles,
  IconTerminal2,
  IconTool,
  IconUser,
  IconUsers,
} from '@tabler/icons-react';
import { Fragment, useCallback, useMemo, useState } from 'react';

import { CreateProjectModal } from 'pages/Projects/CreateProjectModal';
import {
  companyAssetsPath,
  companyConfigItemsPath,
  companyMembersPath,
  companyProjectAgentsPath,
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
  companyProjectWorkflowRunsPath,
  companyProjectWorkflowsPath,
  companyProjectsPath,
  companySessionsPath,
  companyWorkflowCatalogIndexPath,
} from 'shared/routes';

import { ColorSchemeToggle } from './ColorSchemeToggle';
import classes from './AppSidebar.module.css';
import type { SharedPermissions, SharedProject, SharedProps } from './types';

const SIDEBAR_WIDTH = 220;
const SIDEBAR_COLLAPSED_WIDTH = 52;
const STORAGE_KEY = 'sidebar-collapsed';

const getInitials = (name: string): string => {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return 'U';
  if (parts.length === 1) return (parts[0][0] ?? 'U').toUpperCase();
  return ((parts[0][0] ?? 'U') + (parts[parts.length - 1][0] ?? 'U')).toUpperCase();
};

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
      { label: 'Runs', icon: <IconPlayerPlay size={18} />, path: companyProjectWorkflowRunsPath(projectId) },
      { label: 'Sessions', icon: <IconTerminal2 size={18} />, path: companyProjectSessionsPath(projectId) },
      { label: 'Assets', icon: <IconFiles size={18} />, path: companyProjectAssetsPath(projectId) },
    ],
  },
  {
    label: 'Resources',
    items: [
      { label: 'Agents', icon: <IconRobot size={18} />, path: companyProjectAgentsPath(projectId) },
      { label: 'Tools', icon: <IconTool size={18} />, path: companyProjectToolsPath(projectId) },
      { label: 'Skills', icon: <IconSparkles size={18} />, path: companyProjectSkillsPath(projectId) },
      { label: 'MCP Servers', icon: <IconArrowsExchange size={18} />, path: companyProjectMCPServersPath(projectId) },
      { label: 'Repositories', icon: <IconGitBranch size={18} />, path: companyProjectRepositoriesPath(projectId) },
      { label: 'Integrations', icon: <IconPlugConnected size={18} />, path: companyProjectIntegrationsPath(projectId) },
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
      { label: 'Analytics', icon: <IconChartBar size={18} />, path: '/company/analytics' }, // TODO: use companyAnalyticsPath() when route helper is available
      { label: 'Sessions', icon: <IconTerminal2 size={18} />, path: companySessionsPath() },
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
      { label: 'Config Items', icon: <IconKey size={18} />, path: companyConfigItemsPath(), adminOnly: true },
      { label: 'Members', icon: <IconUsers size={18} />, path: companyMembersPath() },
    ],
  },
];

// ─── SidebarNav ───────────────────────────────────────────────────────────────

interface SidebarNavProps {
  groups: NavGroup[];
  collapsed: boolean;
  isAdmin: boolean;
  onNavigate?: () => void;
}

function SidebarNav({ groups, collapsed, isAdmin, onNavigate }: SidebarNavProps) {
  const currentPath = typeof window !== 'undefined' ? window.location.pathname : '';

  return (
    <>
      {groups.map((group, groupIdx) => {
        const visibleItems = group.items.filter((item) => !item.adminOnly || isAdmin);
        if (visibleItems.length === 0) return null;

        return (
          <Fragment key={groupIdx}>
            {group.label && (
              <div className={`${classes.navGroupLabel} ${collapsed ? classes.navGroupLabelCollapsed : ''}`}>
                {group.label}
              </div>
            )}
            {visibleItems.map((item, itemIdx) => {
              const isActive = currentPath === item.path || currentPath.startsWith(item.path + '/');
              const isOverview = groupIdx === 0 && itemIdx === 0 && !group.label;

              if (collapsed) {
                const iconEl = <span className={classes.navItemIconCollapsed}>{item.icon}</span>;
                return (
                  <Tooltip key={item.path} label={item.label} position="right" withArrow>
                    <Link
                      href={item.path}
                      onClick={onNavigate}
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

  const handleProjectClick = (projectId: string) => {
    setPopoverOpen(false);
    router.visit(companyProjectPath(projectId));
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
                  className={`${classes.dpItem} ${isActive ? classes.dpItemActive : ''}`}
                  onClick={() => handleProjectClick(String(project.id))}
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
  const companyName = currentUser?.company?.name ?? '';

  const navGroups = context === 'project' && projectId ? buildProjectNavGroups(projectId) : companyNavGroups;

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
        <SidebarNav groups={navGroups} collapsed={collapsed} isAdmin={isAdmin} onNavigate={onNavigate} />
      </ScrollArea>

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
  const { projects: pageProjects = [], permissions: pagePermissions } = usePage<SharedProps>().props;

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
        <UnstyledButton onClick={openDrawer} className={classes.mobileToggle} aria-label="Open navigation">
          <IconMenu2 size={20} />
        </UnstyledButton>
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
    <nav className={`${classes.root} ${collapsed ? classes.rootCollapsed : ''}`} style={{ width, minWidth: width }}>
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
  );
};
