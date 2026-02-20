import AccountTreeOutlined from '@mui/icons-material/AccountTreeOutlined';
import AutoAwesomeOutlined from '@mui/icons-material/AutoAwesomeOutlined';
import BuildOutlined from '@mui/icons-material/BuildOutlined';
import ChevronLeft from '@mui/icons-material/ChevronLeft';
import ChevronRight from '@mui/icons-material/ChevronRight';
import DnsOutlined from '@mui/icons-material/DnsOutlined';
import ExtensionOutlined from '@mui/icons-material/ExtensionOutlined';
import FolderOutlined from '@mui/icons-material/FolderOutlined';
import GroupOutlined from '@mui/icons-material/GroupOutlined';
import InsertDriveFileOutlined from '@mui/icons-material/InsertDriveFileOutlined';
import SmartToyOutlined from '@mui/icons-material/SmartToyOutlined';
import TerminalOutlined from '@mui/icons-material/TerminalOutlined';
import VpnKeyOutlined from '@mui/icons-material/VpnKeyOutlined';
import { Box, Divider, IconButton, List, ListItemButton, ListItemIcon, ListItemText, Tooltip } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { Link, useRouterState } from '@tanstack/react-router';
import { Fragment, useCallback, useState } from 'react';

import { useGetCurrentUserQuery } from 'entities/user';
import { Routes } from 'shared/routes';

const SIDEBAR_WIDTH = 240;
const SIDEBAR_COLLAPSED_WIDTH = 64;
const STORAGE_KEY = 'sidebar-collapsed';

interface NavItem {
  path: string;
  label: string;
  icon: React.ReactElement;
  adminOnly?: boolean;
}

const navGroups: NavItem[][] = [
  [
    { path: Routes.frontend.companyProjectsPath, label: 'Projects', icon: <FolderOutlined /> },
    { path: Routes.frontend.companySessionsPath, label: 'Sessions', icon: <TerminalOutlined /> },
  ],
  [
    { path: Routes.frontend.companyAgentsPath, label: 'Agents', icon: <SmartToyOutlined />, adminOnly: true },
    { path: Routes.frontend.companyToolsPath, label: 'Tools', icon: <BuildOutlined />, adminOnly: true },
    { path: Routes.frontend.companyMcpServersPath, label: 'MCP Servers', icon: <DnsOutlined />, adminOnly: true },
    { path: Routes.frontend.companySkillsPath, label: 'Skills', icon: <AutoAwesomeOutlined />, adminOnly: true },
  ],
  [
    { path: Routes.frontend.companyMembersPath, label: 'Members', icon: <GroupOutlined />, adminOnly: true },
    {
      path: Routes.frontend.companyIntegrationsPath,
      label: 'Integrations',
      icon: <ExtensionOutlined />,
      adminOnly: true,
    },
    {
      path: Routes.frontend.companyRepositoriesPath,
      label: 'Repositories',
      icon: <AccountTreeOutlined />,
      adminOnly: true,
    },
    {
      path: Routes.frontend.companyConfigItemsPath,
      label: 'Secrets & Variables',
      icon: <VpnKeyOutlined />,
      adminOnly: true,
    },
    {
      path: Routes.frontend.companyAssetsPath,
      label: 'Assets',
      icon: <InsertDriveFileOutlined />,
      adminOnly: true,
    },
  ],
];

const isActive = (itemPath: string, currentPath: string) =>
  currentPath === itemPath || currentPath.startsWith(itemPath + '/');

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
    my: 1,
    mx: 1.5,
  },
  toggleContainer: {
    p: 1.5,
  },
  toggleButton: {
    border: '1px solid',
    borderColor: 'divider',
    borderRadius: 1,
    width: 32,
    height: 32,
    '&:hover': {
      backgroundColor: 'action.hover',
      borderColor: 'text.secondary',
    },
  },
} satisfies Record<string, SxProps<Theme>>;

const getItemStyles = (active: boolean, collapsed: boolean): SxProps<Theme> => ({
  minHeight: 44,
  px: 2,
  borderLeft: '3px solid',
  borderColor: active ? 'primary.main' : 'transparent',
  backgroundColor: active ? 'action.selected' : 'transparent',
  '&:hover': {
    backgroundColor: active ? 'action.selected' : 'action.hover',
  },
  justifyContent: collapsed ? 'center' : 'flex-start',
});

const getIconStyles = (active: boolean, collapsed: boolean): SxProps<Theme> => ({
  minWidth: collapsed ? 0 : 36,
  color: active ? 'primary.main' : 'text.secondary',
  justifyContent: 'center',
});

export const AppSidebar: React.FC = () => {
  const routerState = useRouterState();
  const { data: currentUser } = useGetCurrentUserQuery();
  const [collapsed, setCollapsed] = useState(() => localStorage.getItem(STORAGE_KEY) === 'true');

  const currentPath = routerState.location.pathname;
  const isAdmin = currentUser?.role === 'admin';
  const width = collapsed ? SIDEBAR_COLLAPSED_WIDTH : SIDEBAR_WIDTH;

  const toggleCollapsed = useCallback(() => {
    setCollapsed((prev) => {
      const next = !prev;
      localStorage.setItem(STORAGE_KEY, String(next));
      return next;
    });
  }, []);

  const visibleGroups = navGroups
    .map((group) => group.filter((item) => !item.adminOnly || isAdmin))
    .filter((group) => group.length > 0);

  return (
    <Box component="nav" sx={{ ...styles.root, width, minWidth: width }}>
      <Box sx={styles.listContainer}>
        {visibleGroups.map((group, groupIdx) => (
          <Fragment key={groupIdx}>
            {groupIdx > 0 && <Divider sx={styles.divider} />}
            <List disablePadding>
              {group.map((item) => {
                const itemActive = isActive(item.path, currentPath);
                return (
                  <Tooltip key={item.path} title={collapsed ? item.label : ''} placement="right" arrow>
                    <ListItemButton component={Link} to={item.path} sx={getItemStyles(itemActive, collapsed)}>
                      <ListItemIcon sx={getIconStyles(itemActive, collapsed)}>{item.icon}</ListItemIcon>
                      {!collapsed && (
                        <ListItemText
                          primary={item.label}
                          primaryTypographyProps={{
                            fontSize: 14,
                            fontWeight: itemActive ? 600 : 500,
                            color: itemActive ? 'text.primary' : 'text.secondary',
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
        <Tooltip title={collapsed ? 'Expand sidebar' : 'Collapse sidebar'} placement="right" arrow>
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
