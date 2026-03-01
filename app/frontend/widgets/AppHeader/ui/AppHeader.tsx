import AccountTreeOutlined from '@mui/icons-material/AccountTreeOutlined';
import ArrowDropDown from '@mui/icons-material/ArrowDropDown';
import AutoAwesomeOutlined from '@mui/icons-material/AutoAwesomeOutlined';
import BuildOutlined from '@mui/icons-material/BuildOutlined';
import BusinessIcon from '@mui/icons-material/Business';
import DnsOutlined from '@mui/icons-material/DnsOutlined';
import ExtensionOutlined from '@mui/icons-material/ExtensionOutlined';
import FolderOutlined from '@mui/icons-material/FolderOutlined';
import GroupOutlined from '@mui/icons-material/GroupOutlined';
import InsertDriveFileOutlined from '@mui/icons-material/InsertDriveFileOutlined';
import LogoutIcon from '@mui/icons-material/Logout';
import PersonIcon from '@mui/icons-material/Person';
import SettingsOutlined from '@mui/icons-material/SettingsOutlined';
import SmartToyOutlined from '@mui/icons-material/SmartToyOutlined';
import SourceOutlined from '@mui/icons-material/SourceOutlined';
import TerminalOutlined from '@mui/icons-material/TerminalOutlined';
import VpnKeyOutlined from '@mui/icons-material/VpnKeyOutlined';
import WorkOutlined from '@mui/icons-material/WorkOutlined';
import {
  AppBar,
  Avatar,
  Box,
  Button,
  Divider,
  IconButton,
  ListItemIcon,
  ListItemText,
  Menu,
  MenuItem,
  Toolbar,
  Typography,
} from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { Link, useNavigate, useParams, useRouterState } from '@tanstack/react-router';
import { useEffect, useState } from 'react';

import { useAllProjectsQuery } from 'entities/project';
import { useGetCurrentUserQuery } from 'entities/user';
import { Routes } from 'shared/routes';

import { setSelectedProjectId } from '../lib/selectedProject';

interface DropdownMenuConfig {
  label: string;
  icon: React.ReactElement;
  items: {
    path: string;
    label: string;
    icon: React.ReactElement;
    adminOnly?: boolean;
  }[];
}

const styles = {
  appBar: {
    backgroundColor: 'background.paper',
    borderBottom: '1px solid',
    borderColor: 'divider',
    boxShadow: 'none',
    zIndex: (theme: Theme) => theme.zIndex.drawer + 1,
  },
  toolbar: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    minHeight: '48px !important',
    padding: '0 16px',
    gap: 1,
  },
  leftSection: {
    display: 'flex',
    alignItems: 'center',
    gap: 1,
  },
  logoSection: {
    display: 'flex',
    alignItems: 'center',
    textDecoration: 'none',
    mr: 2,
  },
  companyLogo: {
    height: 28,
    maxWidth: 120,
    objectFit: 'contain' as const,
  },
  companyLogoPlaceholder: {
    width: 28,
    height: 28,
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'action.hover',
    borderRadius: 1,
    color: 'text.secondary',
  },
  navButton: {
    textTransform: 'none',
    fontSize: '13px',
    fontWeight: 500,
    color: 'text.secondary',
    '&:hover': {
      backgroundColor: 'action.hover',
      color: 'text.primary',
    },
    minHeight: 36,
    px: 1.5,
  },
  navButtonActive: {
    color: 'text.primary',
    fontWeight: 600,
  },
  projectSelector: {
    textTransform: 'none',
    fontSize: '13px',
    fontWeight: 500,
    color: 'text.primary',
    backgroundColor: 'action.hover',
    '&:hover': {
      backgroundColor: 'action.selected',
    },
    minHeight: 36,
    px: 1.5,
    borderRadius: 1,
  },
  rightSection: {
    display: 'flex',
    alignItems: 'center',
    gap: 1,
  },
  userName: {
    fontSize: '13px',
    fontWeight: 500,
    color: 'text.primary',
  },
  avatar: {
    width: 32,
    height: 32,
    backgroundColor: 'primary.main',
    fontSize: '13px',
    fontWeight: 600,
    cursor: 'pointer',
    '&:hover': { opacity: 0.9 },
  },
  menuPaper: {
    mt: 1.5,
    minWidth: 200,
    backgroundColor: 'background.paper',
    border: '1px solid',
    borderColor: 'divider',
  },
  menuItem: {
    padding: '8px 16px',
    '&:hover': { backgroundColor: 'action.hover' },
  },
  menuItemActive: {
    backgroundColor: 'action.selected',
  },
  menuItemText: {
    fontSize: '14px',
    color: 'text.primary',
  },
  menuItemIcon: {
    minWidth: '36px',
    color: 'text.secondary',
  },
} satisfies Record<string, SxProps<Theme> | React.CSSProperties>;

const getInitials = (name: string): string => {
  const parts = name.trim().split(/\s+/);
  if (parts.length === 1) return parts[0].substring(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
};

const dropdownMenus: DropdownMenuConfig[] = [
  {
    label: 'Work',
    icon: <WorkOutlined fontSize="small" />,
    items: [
      { path: Routes.frontend.companySessionsPath, label: 'Sessions', icon: <TerminalOutlined fontSize="small" /> },
      {
        path: Routes.frontend.companyWorkflowsPath,
        label: 'Workflows',
        icon: <AccountTreeOutlined fontSize="small" />,
      },
      {
        path: Routes.frontend.companyAssetsPath,
        label: 'Assets',
        icon: <InsertDriveFileOutlined fontSize="small" />,
        adminOnly: true,
      },
    ],
  },
  {
    label: 'Agent Context',
    icon: <SmartToyOutlined fontSize="small" />,
    items: [
      {
        path: Routes.frontend.companyAgentsPath,
        label: 'Agents',
        icon: <SmartToyOutlined fontSize="small" />,
        adminOnly: true,
      },
      {
        path: Routes.frontend.companyToolsPath,
        label: 'Tools',
        icon: <BuildOutlined fontSize="small" />,
        adminOnly: true,
      },
      {
        path: Routes.frontend.companyMcpServersPath,
        label: 'MCP Servers',
        icon: <DnsOutlined fontSize="small" />,
        adminOnly: true,
      },
      {
        path: Routes.frontend.companySkillsPath,
        label: 'Skills',
        icon: <AutoAwesomeOutlined fontSize="small" />,
        adminOnly: true,
      },
    ],
  },
  {
    label: 'Settings',
    icon: <SettingsOutlined fontSize="small" />,
    items: [
      {
        path: Routes.frontend.companyIntegrationsPath,
        label: 'Integrations',
        icon: <ExtensionOutlined fontSize="small" />,
        adminOnly: true,
      },
      {
        path: Routes.frontend.companyRepositoriesPath,
        label: 'Repositories',
        icon: <SourceOutlined fontSize="small" />,
        adminOnly: true,
      },
      {
        path: Routes.frontend.companyConfigItemsPath,
        label: 'Secrets & Variables',
        icon: <VpnKeyOutlined fontSize="small" />,
        adminOnly: true,
      },
      {
        path: Routes.frontend.companyMembersPath,
        label: 'Members',
        icon: <GroupOutlined fontSize="small" />,
        adminOnly: true,
      },
    ],
  },
];

export const AppHeader: React.FC = () => {
  const navigate = useNavigate();
  const routerState = useRouterState();
  const params = useParams({ strict: false }) as { projectId?: string };
  const { data: currentUser } = useGetCurrentUserQuery();
  const { data: projectsData } = useAllProjectsQuery();
  const [userAnchor, setUserAnchor] = useState<null | HTMLElement>(null);
  const [projectAnchor, setProjectAnchor] = useState<null | HTMLElement>(null);
  const [menuAnchors, setMenuAnchors] = useState<Record<string, HTMLElement | null>>({});

  const currentPath = routerState.location.pathname;
  const isAdmin = currentUser?.role === 'admin';
  const company = currentUser?.company;
  const projects = projectsData?.items ?? [];

  const currentProjectId = params.projectId || null;
  const currentProject = currentProjectId ? projects.find((p) => String(p.id) === currentProjectId) : null;

  useEffect(() => {
    if (currentProjectId) {
      setSelectedProjectId(currentProjectId);
    }
  }, [currentProjectId]);

  const handleProjectSelect = (projectId: string | null) => {
    setProjectAnchor(null);
    if (projectId) {
      setSelectedProjectId(projectId);
      navigate({ to: Routes.frontend.companyProjectPath(projectId) });
    } else {
      setSelectedProjectId(null);
      navigate({ to: Routes.frontend.companyProjectsPath });
    }
  };

  const handleMenuOpen = (key: string, event: React.MouseEvent<HTMLElement>) => {
    setMenuAnchors((prev) => ({ ...prev, [key]: event.currentTarget }));
  };
  const handleMenuClose = (key: string) => {
    setMenuAnchors((prev) => ({ ...prev, [key]: null }));
  };

  const handleNavItemClick = (key: string, path: string) => {
    handleMenuClose(key);
    navigate({ to: path });
  };

  const handleLogout = async () => {
    setUserAnchor(null);
    try {
      await fetch('/api/v1/sessions', { method: 'DELETE' });
    } catch {
      // noop
    }
    window.location.href = Routes.frontend.loginPath;
  };

  if (!currentUser) return null;

  const renderCompanyLogo = () => {
    if (company?.logoUrl) {
      return <img src={company.logoUrl} alt={company.name} style={styles.companyLogo as React.CSSProperties} />;
    }
    return (
      <Box sx={styles.companyLogoPlaceholder}>
        <BusinessIcon fontSize="small" />
      </Box>
    );
  };

  const isMenuPathActive = (menuItems: DropdownMenuConfig['items']) =>
    menuItems.some((item) => currentPath === item.path || currentPath.startsWith(item.path + '/'));

  return (
    <AppBar position="static" sx={styles.appBar}>
      <Toolbar sx={styles.toolbar}>
        <Box sx={styles.leftSection}>
          <Link to={Routes.frontend.companyProjectsPath} style={styles.logoSection as React.CSSProperties}>
            {renderCompanyLogo()}
          </Link>

          {/* Project Selector */}
          <Button
            onClick={(e) => setProjectAnchor(e.currentTarget)}
            endIcon={<ArrowDropDown />}
            startIcon={<FolderOutlined fontSize="small" />}
            sx={styles.projectSelector}
          >
            {currentProject ? currentProject.name : 'All Projects'}
          </Button>
          <Menu
            anchorEl={projectAnchor}
            open={Boolean(projectAnchor)}
            onClose={() => setProjectAnchor(null)}
            slotProps={{ paper: { sx: styles.menuPaper } }}
          >
            <MenuItem
              onClick={() => handleProjectSelect(null)}
              sx={{
                ...styles.menuItem,
                ...(!currentProjectId ? styles.menuItemActive : {}),
              }}
            >
              <ListItemIcon sx={styles.menuItemIcon}>
                <FolderOutlined fontSize="small" />
              </ListItemIcon>
              <ListItemText primaryTypographyProps={{ sx: styles.menuItemText }}>All Projects</ListItemText>
            </MenuItem>
            <Divider />
            {projects.map((project) => (
              <MenuItem
                key={project.id}
                onClick={() => handleProjectSelect(String(project.id))}
                sx={{
                  ...styles.menuItem,
                  ...(String(project.id) === currentProjectId ? styles.menuItemActive : {}),
                }}
              >
                <ListItemText primaryTypographyProps={{ sx: styles.menuItemText }}>{project.name}</ListItemText>
              </MenuItem>
            ))}
          </Menu>

          <Divider orientation="vertical" flexItem sx={{ mx: 0.5 }} />

          {/* Dropdown menus */}
          {dropdownMenus.map((menu) => {
            const visibleItems = menu.items.filter((item) => !item.adminOnly || isAdmin);
            if (visibleItems.length === 0) return null;
            const isActive = isMenuPathActive(visibleItems);
            return (
              <Box key={menu.label}>
                <Button
                  onClick={(e) => handleMenuOpen(menu.label, e)}
                  endIcon={<ArrowDropDown />}
                  sx={{
                    ...styles.navButton,
                    ...(isActive ? styles.navButtonActive : {}),
                  }}
                >
                  {menu.label}
                </Button>
                <Menu
                  anchorEl={menuAnchors[menu.label]}
                  open={Boolean(menuAnchors[menu.label])}
                  onClose={() => handleMenuClose(menu.label)}
                  slotProps={{ paper: { sx: styles.menuPaper } }}
                >
                  {visibleItems.map((item) => {
                    const itemActive = currentPath === item.path || currentPath.startsWith(item.path + '/');
                    return (
                      <MenuItem
                        key={item.path}
                        onClick={() => handleNavItemClick(menu.label, item.path)}
                        sx={{
                          ...styles.menuItem,
                          ...(itemActive ? styles.menuItemActive : {}),
                        }}
                      >
                        <ListItemIcon sx={styles.menuItemIcon}>{item.icon}</ListItemIcon>
                        <ListItemText primaryTypographyProps={{ sx: styles.menuItemText }}>{item.label}</ListItemText>
                      </MenuItem>
                    );
                  })}
                </Menu>
              </Box>
            );
          })}
        </Box>

        {/* Right section */}
        <Box sx={styles.rightSection}>
          <Typography sx={styles.userName}>{currentUser.name}</Typography>
          <IconButton onClick={(e) => setUserAnchor(e.currentTarget)} size="small" aria-label="User menu">
            <Avatar sx={styles.avatar}>{getInitials(currentUser.name)}</Avatar>
          </IconButton>
          <Menu
            anchorEl={userAnchor}
            open={Boolean(userAnchor)}
            onClose={() => setUserAnchor(null)}
            onClick={() => setUserAnchor(null)}
            slotProps={{ paper: { sx: styles.menuPaper } }}
            transformOrigin={{ horizontal: 'right', vertical: 'top' }}
            anchorOrigin={{ horizontal: 'right', vertical: 'bottom' }}
          >
            <MenuItem onClick={() => navigate({ to: Routes.frontend.profilePath })} sx={styles.menuItem}>
              <ListItemIcon sx={styles.menuItemIcon}>
                <PersonIcon fontSize="small" />
              </ListItemIcon>
              <Typography sx={styles.menuItemText}>My Profile</Typography>
            </MenuItem>
            <Divider />
            <MenuItem onClick={handleLogout} sx={styles.menuItem}>
              <ListItemIcon sx={styles.menuItemIcon}>
                <LogoutIcon fontSize="small" />
              </ListItemIcon>
              <Typography sx={styles.menuItemText}>Sign Out</Typography>
            </MenuItem>
          </Menu>
        </Box>
      </Toolbar>
    </AppBar>
  );
};
