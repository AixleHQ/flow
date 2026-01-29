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
import { Logo } from 'shared/ui';

const styles = {
  appBar: {
    backgroundColor: 'background.paper',
    borderBottom: '1px solid',
    borderColor: 'divider',
    boxShadow: 'none',
  },
  toolbar: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    minHeight: '64px',
    padding: '0 24px',
  },
  logoLink: {
    display: 'flex',
    alignItems: 'center',
    textDecoration: 'none',
  },
  userSection: {
    display: 'flex',
    alignItems: 'center',
    gap: '12px',
  },
  userName: {
    fontSize: '14px',
    fontWeight: 500,
    color: 'text.primary',
  },
  avatar: {
    width: 36,
    height: 36,
    backgroundColor: 'primary.main',
    fontSize: '14px',
    fontWeight: 600,
    cursor: 'pointer',
    '&:hover': {
      opacity: 0.9,
    },
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
    '&:hover': {
      backgroundColor: 'action.hover',
    },
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
} satisfies Record<string, SxProps<Theme>>;

const getInitials = (name: string): string => {
  const parts = name.trim().split(/\s+/);
  if (parts.length === 1) {
    return parts[0].substring(0, 2).toUpperCase();
  }
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
};

export const AppHeader: React.FC = () => {
  const navigate = useNavigate();
  const routerState = useRouterState();
  const { data: currentUser } = useGetCurrentUserQuery();
  const [anchorEl, setAnchorEl] = useState<null | HTMLElement>(null);
  const open = Boolean(anchorEl);

  const isProfileActive = routerState.location.pathname === Routes.frontend.profilePath;

  const handleMenuOpen = (event: React.MouseEvent<HTMLElement>) => {
    setAnchorEl(event.currentTarget);
  };

  const handleMenuClose = () => {
    setAnchorEl(null);
  };

  const handleProfileClick = () => {
    handleMenuClose();
    navigate({ to: Routes.frontend.profilePath });
  };

  const handleLogout = async () => {
    handleMenuClose();
    // Clear session and redirect to login
    try {
      await fetch('/api/v1/logout', { method: 'DELETE' });
    } catch {
      // Ignore errors, we're logging out anyway
    }
    window.location.href = Routes.frontend.loginPath;
  };

  if (!currentUser) {
    return null;
  }

  return (
    <AppBar position="static" sx={styles.appBar}>
      <Toolbar sx={styles.toolbar}>
        {/* Logo */}
        <Link to={Routes.frontend.projectsPath} style={styles.logoLink as React.CSSProperties}>
          <Logo width={100} />
        </Link>

        {/* User Section */}
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

        {/* User Menu */}
        <Menu
          id="user-menu"
          anchorEl={anchorEl}
          open={open}
          onClose={handleMenuClose}
          onClick={handleMenuClose}
          slotProps={{
            paper: {
              sx: styles.menuPaper,
            },
          }}
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
