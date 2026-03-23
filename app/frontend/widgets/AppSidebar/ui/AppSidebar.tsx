import AccountTreeOutlined from '@mui/icons-material/AccountTreeOutlined';
import AutoAwesomeOutlined from '@mui/icons-material/AutoAwesomeOutlined';
import BuildOutlined from '@mui/icons-material/BuildOutlined';
import ChevronLeft from '@mui/icons-material/ChevronLeft';
import ChevronRight from '@mui/icons-material/ChevronRight';
import DashboardOutlined from '@mui/icons-material/DashboardOutlined';
import DnsOutlined from '@mui/icons-material/DnsOutlined';
import GroupOutlined from '@mui/icons-material/GroupOutlined';
import InsertDriveFileOutlined from '@mui/icons-material/InsertDriveFileOutlined';
import LinkOutlined from '@mui/icons-material/LinkOutlined';
import PlaylistPlayOutlined from '@mui/icons-material/PlaylistPlayOutlined';
import SettingsOutlined from '@mui/icons-material/SettingsOutlined';
import SmartToyOutlined from '@mui/icons-material/SmartToyOutlined';
import SourceOutlined from '@mui/icons-material/SourceOutlined';
import TerminalOutlined from '@mui/icons-material/TerminalOutlined';
import TrendingUpOutlined from '@mui/icons-material/TrendingUpOutlined';
import ViewKanbanOutlined from '@mui/icons-material/ViewKanbanOutlined';
import VpnKeyOutlined from '@mui/icons-material/VpnKeyOutlined';
import { Box, Divider, IconButton, List, ListItemButton, ListItemIcon, ListItemText, Tooltip } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { Link, useParams, useRouterState } from '@tanstack/react-router';
import { Fragment, useCallback, useState } from 'react';

import { Routes } from 'shared/routes';

const SIDEBAR_WIDTH = 220;
const SIDEBAR_COLLAPSED_WIDTH = 56;
const STORAGE_KEY = 'sidebar-collapsed';

interface NavItem {
  tab: string;
  label: string;
  icon: React.ReactElement;
}

const navGroups: NavItem[][] = [
  [
    { tab: 'overview', label: 'Overview', icon: <DashboardOutlined /> },
    { tab: 'board', label: 'Tasks', icon: <ViewKanbanOutlined /> },
    { tab: 'sessions', label: 'Sessions', icon: <TerminalOutlined /> },
    { tab: 'workflows', label: 'Workflows', icon: <AccountTreeOutlined /> },
    { tab: 'workflow-runs', label: 'Runs', icon: <PlaylistPlayOutlined /> },
    { tab: 'assets', label: 'Assets', icon: <InsertDriveFileOutlined /> },
    { tab: 'analytics', label: 'Analytics', icon: <TrendingUpOutlined /> },
  ],
  [
    { tab: 'repositories', label: 'Repositories', icon: <SourceOutlined /> },
    { tab: 'integrations', label: 'Integrations', icon: <LinkOutlined /> },
    { tab: 'agents', label: 'Agents', icon: <SmartToyOutlined /> },
    { tab: 'tools', label: 'Tools', icon: <BuildOutlined /> },
    { tab: 'mcp-servers', label: 'MCP Servers', icon: <DnsOutlined /> },
    { tab: 'skills', label: 'Skills', icon: <AutoAwesomeOutlined /> },
  ],
  [
    { tab: 'config', label: 'Secrets & Variables', icon: <VpnKeyOutlined /> },
    { tab: 'members', label: 'Members', icon: <GroupOutlined /> },
    { tab: 'settings', label: 'Settings', icon: <SettingsOutlined /> },
  ],
];

const styles = {
  root: {
    display: 'flex',
    flexDirection: 'column',
    borderRight: '1px solid',
    borderColor: 'divider',
    backgroundColor: 'background.paper',
    transition: 'width 0.2s ease, min-width 0.2s ease',
    overflowX: 'hidden',
  },
  listContainer: {
    flex: 1,
    overflowY: 'auto',
    overflowX: 'hidden',
    pt: 1,
  },
  divider: {
    my: 0.5,
    mx: 1.5,
  },
  toggleContainer: {
    p: 1,
  },
  toggleButton: {
    border: '1px solid',
    borderColor: 'divider',
    borderRadius: 1,
    width: 28,
    height: 28,
    '&:hover': {
      backgroundColor: 'action.hover',
      borderColor: 'text.secondary',
    },
  },
} satisfies Record<string, SxProps<Theme>>;

const getItemStyles = (active: boolean, collapsed: boolean): SxProps<Theme> => ({
  minHeight: 36,
  px: collapsed ? 1 : 1.5,
  mx: collapsed ? 0.5 : 1,
  borderRadius: 1,
  backgroundColor: active ? 'action.selected' : 'transparent',
  '&:hover': {
    backgroundColor: active ? 'action.selected' : 'action.hover',
  },
  justifyContent: collapsed ? 'center' : 'flex-start',
});

const getIconStyles = (active: boolean, collapsed: boolean): SxProps<Theme> => ({
  minWidth: collapsed ? 0 : 32,
  color: active ? 'primary.main' : 'text.secondary',
  justifyContent: 'center',
  '& .MuiSvgIcon-root': {
    fontSize: 20,
  },
});

export const AppSidebar: React.FC = () => {
  const routerState = useRouterState();
  const params = useParams({ strict: false }) as { projectId?: string; tab?: string };
  const [collapsed, setCollapsed] = useState(() => localStorage.getItem(STORAGE_KEY) === 'true');

  const projectId = params.projectId;
  const currentTab = params.tab || '';
  const currentPath = routerState.location.pathname;
  const isProjectRoute = currentPath.startsWith('/company/projects/') && projectId;
  const width = collapsed ? SIDEBAR_COLLAPSED_WIDTH : SIDEBAR_WIDTH;

  const toggleCollapsed = useCallback(() => {
    setCollapsed((prev) => {
      const next = !prev;
      localStorage.setItem(STORAGE_KEY, String(next));
      return next;
    });
  }, []);

  if (!isProjectRoute) return null;

  return (
    <Box component="nav" sx={{ ...styles.root, width, minWidth: width }}>
      <Box sx={styles.listContainer}>
        {navGroups.map((group, groupIdx) => (
          <Fragment key={groupIdx}>
            {groupIdx > 0 && <Divider sx={styles.divider} />}
            <List disablePadding>
              {group.map((item) => {
                const isActive = currentTab === item.tab || currentPath.includes(item.tab);
                const to = Routes.frontend.companyProjectTabPath(projectId!, item.tab);
                return (
                  <Tooltip key={item.tab} title={collapsed ? item.label : ''} placement="right" arrow>
                    <ListItemButton component={Link} to={to} sx={getItemStyles(isActive, collapsed)}>
                      <ListItemIcon sx={getIconStyles(isActive, collapsed)}>{item.icon}</ListItemIcon>
                      {!collapsed && (
                        <ListItemText
                          primary={item.label}
                          primaryTypographyProps={{
                            fontSize: 13,
                            lineHeight: 1.7,
                            fontWeight: isActive ? 600 : 400,
                            color: isActive ? 'text.primary' : 'text.secondary',
                            noWrap: true,
                          }}
                        />
                      )}
                    </ListItemButton>
                  </Tooltip>
                );
              })}
            </List>
          </Fragment>
        ))}
      </Box>

      <Divider />
      <Box sx={{ ...styles.toggleContainer, display: 'flex', justifyContent: collapsed ? 'center' : 'flex-end' }}>
        <Tooltip title={collapsed ? 'Expand' : 'Collapse'} placement="right" arrow>
          <IconButton
            onClick={toggleCollapsed}
            size="small"
            sx={styles.toggleButton}
            aria-label={collapsed ? 'Expand sidebar' : 'Collapse sidebar'}
          >
            {collapsed ? <ChevronRight fontSize="small" /> : <ChevronLeft fontSize="small" />}
          </IconButton>
        </Tooltip>
      </Box>
    </Box>
  );
};
