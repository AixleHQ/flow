import { Link } from '@inertiajs/react';
import { Box, Divider, Drawer, NavLink, ScrollArea, Tooltip, UnstyledButton } from '@mantine/core';
import { useDisclosure, useMediaQuery } from '@mantine/hooks';
import {
  IconBolt,
  IconChartBar,
  IconChevronLeft,
  IconChevronRight,
  IconDeviceDesktopAnalytics,
  IconFileText,
  IconKey,
  IconLink,
  IconListDetails,
  IconMenu2,
  IconPlayerPlay,
  IconServer,
  IconSettings,
  IconSourceCode,
  IconStar,
  IconTerminal2,
  IconTool,
  IconTrendingUp,
  IconUsers,
} from '@tabler/icons-react';
import { Fragment, useCallback, useState } from 'react';

import classes from './AppSidebar.module.css';

const SIDEBAR_WIDTH = 220;
const SIDEBAR_COLLAPSED_WIDTH = 56;
const STORAGE_KEY = 'sidebar-collapsed';

interface NavItem {
  tab: string;
  label: string;
  icon: React.ReactNode;
}

const navGroups: NavItem[][] = [
  [
    { tab: 'overview', label: 'Overview', icon: <IconChartBar size={20} /> },
    { tab: 'board', label: 'Tasks', icon: <IconListDetails size={20} /> },
    { tab: 'sessions', label: 'Sessions', icon: <IconTerminal2 size={20} /> },
    { tab: 'workflows', label: 'Workflows', icon: <IconDeviceDesktopAnalytics size={20} /> },
    { tab: 'workflow_runs', label: 'Runs', icon: <IconPlayerPlay size={20} /> },
    { tab: 'assets', label: 'Assets', icon: <IconFileText size={20} /> },
    { tab: 'analytics', label: 'Analytics', icon: <IconTrendingUp size={20} /> },
  ],
  [
    { tab: 'repositories', label: 'Repositories', icon: <IconSourceCode size={20} /> },
    { tab: 'integrations', label: 'Integrations', icon: <IconLink size={20} /> },
    { tab: 'agents', label: 'Agents', icon: <IconBolt size={20} /> },
    { tab: 'tools', label: 'Tools', icon: <IconTool size={20} /> },
    { tab: 'mcp_servers', label: 'MCP Servers', icon: <IconServer size={20} /> },
    { tab: 'skills', label: 'Skills', icon: <IconStar size={20} /> },
  ],
  [
    { tab: 'config_items', label: 'Secrets & Variables', icon: <IconKey size={20} /> },
    { tab: 'members', label: 'Members', icon: <IconUsers size={20} /> },
    { tab: 'settings', label: 'Settings', icon: <IconSettings size={20} /> },
  ],
];

interface AppSidebarProps {
  projectId: string;
  currentTab?: string;
}

function SidebarNav({
  projectId,
  currentTab,
  collapsed,
  onNavigate,
}: {
  projectId: string;
  currentTab: string;
  collapsed: boolean;
  onNavigate?: () => void;
}) {
  const currentPath = typeof window !== 'undefined' ? window.location.pathname : '';

  return (
    <>
      {navGroups.map((group, groupIdx) => (
        <Fragment key={groupIdx}>
          {groupIdx > 0 && <Divider my={4} mx={12} style={{ borderColor: 'var(--app-border-default)' }} />}
          {group.map((item) => {
            const isActive = currentTab === item.tab || currentPath.includes(item.tab);
            const to = `/company/projects/${projectId}/${item.tab}`;

            if (collapsed) {
              return (
                <Tooltip key={item.tab} label={item.label} position="right" withArrow>
                  <NavLink
                    component={Link}
                    href={to}
                    onClick={onNavigate}
                    active={isActive}
                    leftSection={item.icon}
                    className={classes.navLinkCollapsed}
                  />
                </Tooltip>
              );
            }

            return (
              <NavLink
                key={item.tab}
                component={Link}
                href={to}
                onClick={onNavigate}
                label={item.label}
                active={isActive}
                leftSection={item.icon}
                className={classes.navLink}
                styles={{
                  label: {
                    fontSize: 13,
                    fontWeight: isActive ? 600 : 400,
                  },
                }}
              />
            );
          })}
        </Fragment>
      ))}
    </>
  );
}

export const AppSidebar = ({ projectId, currentTab = '' }: AppSidebarProps) => {
  const [collapsed, setCollapsed] = useState(() => localStorage.getItem(STORAGE_KEY) === 'true');
  const isMobile = useMediaQuery('(max-width: 768px)');
  const [drawerOpened, { open: openDrawer, close: closeDrawer }] = useDisclosure(false);
  const width = collapsed ? SIDEBAR_COLLAPSED_WIDTH : SIDEBAR_WIDTH;

  const toggleCollapsed = useCallback(() => {
    setCollapsed((prev) => {
      const next = !prev;
      localStorage.setItem(STORAGE_KEY, String(next));
      return next;
    });
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
          styles={{ body: { padding: 0, height: '100%', backgroundColor: 'var(--app-bg-paper)' } }}
        >
          <ScrollArea h="100%" type="never" pt={4}>
            <SidebarNav projectId={projectId} currentTab={currentTab} collapsed={false} onNavigate={closeDrawer} />
          </ScrollArea>
        </Drawer>
      </>
    );
  }

  return (
    <Box component="nav" className={classes.root} style={{ width, minWidth: width }}>
      <ScrollArea className={classes.scrollArea} type="never">
        <SidebarNav projectId={projectId} currentTab={currentTab} collapsed={collapsed} />
      </ScrollArea>

      <Divider style={{ borderColor: 'var(--app-border-default)' }} />
      <Box className={classes.toggleContainer} style={{ justifyContent: collapsed ? 'center' : 'flex-end' }}>
        <Tooltip label={collapsed ? 'Expand' : 'Collapse'} position="right" withArrow>
          <UnstyledButton
            onClick={toggleCollapsed}
            className={classes.toggleButton}
            aria-label={collapsed ? 'Expand sidebar' : 'Collapse sidebar'}
          >
            {collapsed ? <IconChevronRight size={16} /> : <IconChevronLeft size={16} />}
          </UnstyledButton>
        </Tooltip>
      </Box>
    </Box>
  );
};
