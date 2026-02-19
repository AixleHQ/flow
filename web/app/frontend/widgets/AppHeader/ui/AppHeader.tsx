import BusinessIcon from '@mui/icons-material/Business';
import LogoutIcon from '@mui/icons-material/Logout';
import PersonIcon from '@mui/icons-material/Person';
import {
  AppBar,
  Avatar,
  Box,
  Divider,
  IconButton,
  ListItemIcon,
  Menu,
  MenuItem,
  Toolbar,
  Typography,
} from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { Link, useNavigate, useRouterState } from '@tanstack/react-router';
import { useState } from 'react';

import { useGetCurrentUserQuery } from 'entities/user';
import { Routes } from 'shared/routes';

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
  },
  logoSection: {
    display: 'flex',
    alignItems: 'center',
    textDecoration: 'none',
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
  userSection: {
    display: 'flex',
    alignItems: 'center',
    gap: '10px',
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
    minWidth: 180,
    backgroundColor: 'background.paper',
    border: '1px solid',
    borderColor: 'divider',
  },
  menuItem: {
    padding: '10px 16px',
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

export const AppHeader: React.FC = () => {
  const navigate = useNavigate();
  const routerState = useRouterState();
  const { data: currentUser } = useGetCurrentUserQuery();
  const [anchorEl, setAnchorEl] = useState<null | HTMLElement>(null);
  const open = Boolean(anchorEl);

  const isProfileActive = routerState.location.pathname === Routes.frontend.profilePath;
  const company = currentUser?.company;

  const handleMenuOpen = (event: React.MouseEvent<HTMLElement>) => setAnchorEl(event.currentTarget);
  const handleMenuClose = () => setAnchorEl(null);

  const handleProfileClick = () => {
    handleMenuClose();
    navigate({ to: Routes.frontend.profilePath });
  };

  const handleLogout = async () => {
    handleMenuClose();
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

  return (
    <AppBar position="static" sx={styles.appBar}>
      <Toolbar sx={styles.toolbar}>
        <Link to={Routes.frontend.companyProjectsPath} style={styles.logoSection as React.CSSProperties}>
          {renderCompanyLogo()}
        </Link>

        <Box sx={styles.userSection}>
          <Typography sx={styles.userName}>{currentUser.name}</Typography>
          <IconButton
            onClick={handleMenuOpen}
            size="small"
            aria-label="User menu"
            aria-controls={open ? 'user-menu' : undefined}
            aria-haspopup="true"
            aria-expanded={open ? 'true' : undefined}
          >
            <Avatar sx={styles.avatar}>{getInitials(currentUser.name)}</Avatar>
          </IconButton>
        </Box>

        <Menu
          id="user-menu"
          anchorEl={anchorEl}
          open={open}
          onClose={handleMenuClose}
          onClick={handleMenuClose}
          slotProps={{ paper: { sx: styles.menuPaper } }}
          transformOrigin={{ horizontal: 'right', vertical: 'top' }}
          anchorOrigin={{ horizontal: 'right', vertical: 'bottom' }}
        >
          <MenuItem
            onClick={handleProfileClick}
            sx={{ ...styles.menuItem, ...(isProfileActive ? styles.menuItemActive : {}) }}
          >
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
      </Toolbar>
    </AppBar>
  );
};
