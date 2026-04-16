import { Link, router, usePage } from '@inertiajs/react';
import {
  ActionIcon,
  Avatar,
  Box,
  Button,
  type ButtonProps,
  Divider,
  Group,
  Menu,
  Text,
  UnstyledButton,
} from '@mantine/core';
import {
  IconBolt,
  IconBriefcase,
  IconBuilding,
  IconChevronDown,
  IconDeviceDesktopAnalytics,
  IconFileText,
  IconFolder,
  IconKey,
  IconLogout,
  IconPlug,
  IconServer,
  IconSettings,
  IconSlash,
  IconSourceCode,
  IconStar,
  IconTerminal2,
  IconTool,
  IconUser,
  IconUsers,
} from '@tabler/icons-react';
import { useEffect, useState } from 'react';

import classes from './AppHeader.module.css';
import type { SharedProps, SharedProject } from './types';

const contextSwitcherStyles: ButtonProps['styles'] = {
  root: {
    textTransform: 'none',
    fontSize: 13,
    fontWeight: 500,
    color: 'var(--app-text-primary)',
    backgroundColor: 'var(--app-action-hover)',
    borderRadius: 4,
    minHeight: 36,
    padding: '0 12px',
    maxWidth: 280,
  },
  label: {
    overflow: 'hidden',
  },
};

const navButtonStyles = (active: boolean): ButtonProps['styles'] => ({
  root: {
    textTransform: 'none',
    fontSize: 13,
    fontWeight: active ? 600 : 500,
    color: active ? 'var(--app-text-primary)' : 'var(--app-text-secondary)',
    minHeight: 36,
    padding: '0 12px',
  },
});

const SELECTED_PROJECT_KEY = 'selected-project-id';

const getSelectedProjectId = (): string | null => localStorage.getItem(SELECTED_PROJECT_KEY);
const setSelectedProjectId = (id: string | null) => {
  if (id) {
    localStorage.setItem(SELECTED_PROJECT_KEY, id);
  } else {
    localStorage.removeItem(SELECTED_PROJECT_KEY);
  }
};

interface DropdownMenuConfig {
  label: string;
  icon: React.ReactNode;
  items: {
    path: string;
    label: string;
    icon: React.ReactNode;
    adminOnly?: boolean;
  }[];
}

const dropdownMenus: DropdownMenuConfig[] = [
  {
    label: 'Work',
    icon: <IconBriefcase size={16} />,
    items: [
      { path: '/company/sessions', label: 'Sessions', icon: <IconTerminal2 size={16} /> },
      { path: '/company/workflows', label: 'Workflows', icon: <IconDeviceDesktopAnalytics size={16} /> },
      { path: '/company/assets', label: 'Assets', icon: <IconFileText size={16} />, adminOnly: true },
    ],
  },
  {
    label: 'Agent Context',
    icon: <IconBolt size={16} />,
    items: [
      { path: '/company/agents', label: 'Agents', icon: <IconBolt size={16} />, adminOnly: true },
      { path: '/company/tools', label: 'Tools', icon: <IconTool size={16} />, adminOnly: true },
      { path: '/company/mcp_servers', label: 'MCP Servers', icon: <IconServer size={16} />, adminOnly: true },
      { path: '/company/skills', label: 'Skills', icon: <IconStar size={16} />, adminOnly: true },
    ],
  },
  {
    label: 'Settings',
    icon: <IconSettings size={16} />,
    items: [
      { path: '/company/integrations', label: 'Integrations', icon: <IconPlug size={16} />, adminOnly: true },
      { path: '/company/repositories', label: 'Repositories', icon: <IconSourceCode size={16} />, adminOnly: true },
      { path: '/company/config_items', label: 'Secrets & Variables', icon: <IconKey size={16} />, adminOnly: true },
      { path: '/company/members', label: 'Members', icon: <IconUsers size={16} />, adminOnly: true },
    ],
  },
];

const getInitials = (name: string): string => {
  const parts = name.trim().split(/\s+/);
  if (parts.length === 1) return parts[0].substring(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
};

interface AppHeaderProps {
  currentProjectId?: string | null;
  currentTab?: string;
}

const isProjectScopedPath = (path: string): boolean => /^\/company\/projects\/\d+/.test(path);

export const AppHeader = ({ currentProjectId: propProjectId }: AppHeaderProps) => {
  const { currentUser, projects = [], permissions } = usePage<SharedProps>().props;
  const currentPath = typeof window !== 'undefined' ? window.location.pathname : '/';
  const onProjectPage = isProjectScopedPath(currentPath);

  const resolvedProjectId = propProjectId ?? (onProjectPage ? getSelectedProjectId() : null);
  const [currentProjectId, setCurrentProjectId] = useState<string | null>(resolvedProjectId);

  const isAdmin = permissions?.isAdmin ?? false;
  const company = currentUser?.company;
  const currentProject = currentProjectId
    ? projects.find((p: SharedProject) => String(p.id) === currentProjectId)
    : null;

  useEffect(() => {
    if (propProjectId) {
      setSelectedProjectId(propProjectId);
      setCurrentProjectId(propProjectId);
    } else if (!onProjectPage) {
      setCurrentProjectId(null);
    }
  }, [propProjectId, onProjectPage]);

  const handleProjectSelect = (projectId: string | null) => {
    if (projectId) {
      setSelectedProjectId(projectId);
      setCurrentProjectId(projectId);
      router.visit(`/company/projects/${projectId}`);
    } else {
      setSelectedProjectId(null);
      setCurrentProjectId(null);
      router.visit('/company/projects');
    }
  };

  const handleLogout = () => {
    router.delete('/logout');
  };

  if (!currentUser) return null;

  const isMenuPathActive = (items: DropdownMenuConfig['items']) =>
    items.some((item) => currentPath === item.path || currentPath.startsWith(item.path + '/'));

  const renderCompanyLogo = () => {
    if (company?.logoUrl) {
      return <img src={company.logoUrl} alt={company.name} className={classes.companyLogo} />;
    }
    return (
      <Box className={classes.companyLogoPlaceholder}>
        <IconBuilding size={16} />
      </Box>
    );
  };

  return (
    <Box component="header" className={classes.header}>
      <Group gap="xs" className={classes.leftSection}>
        <UnstyledButton component={Link} href="/company/projects" className={classes.logoLink}>
          {renderCompanyLogo()}
        </UnstyledButton>

        <Menu shadow="md" width={220}>
          <Menu.Target>
            <Button
              variant="subtle"
              size="compact-md"
              rightSection={<IconChevronDown size={14} />}
              styles={contextSwitcherStyles}
            >
              <Group gap={6} wrap="nowrap">
                <Text size="xs" c="dimmed" truncate>
                  {company?.name ?? 'Company'}
                </Text>
                <IconSlash size={12} style={{ color: 'var(--app-text-tertiary)', flexShrink: 0 }} />
                <Text size="xs" fw={500} truncate>
                  {currentProject ? currentProject.name : 'All Projects'}
                </Text>
              </Group>
            </Button>
          </Menu.Target>
          <Menu.Dropdown>
            <Menu.Item
              leftSection={<IconFolder size={16} />}
              onClick={() => handleProjectSelect(null)}
              className={!currentProjectId ? classes.menuItemActive : undefined}
            >
              All Projects
            </Menu.Item>
            <Menu.Divider />
            {projects.map((project: SharedProject) => (
              <Menu.Item
                key={project.id}
                onClick={() => handleProjectSelect(String(project.id))}
                className={String(project.id) === currentProjectId ? classes.menuItemActive : undefined}
              >
                {project.name}
              </Menu.Item>
            ))}
          </Menu.Dropdown>
        </Menu>

        <Divider orientation="vertical" mx={4} style={{ borderColor: 'var(--app-border-default)' }} />

        {/* Dropdown menus */}
        {dropdownMenus.map((menu) => {
          const visibleItems = menu.items.filter((item) => !item.adminOnly || isAdmin);
          if (visibleItems.length === 0) return null;
          const isActive = isMenuPathActive(visibleItems);

          return (
            <Menu key={menu.label} shadow="md" width={200}>
              <Menu.Target>
                <Button
                  variant="subtle"
                  size="compact-md"
                  rightSection={<IconChevronDown size={14} />}
                  styles={navButtonStyles(isActive)}
                >
                  {menu.label}
                </Button>
              </Menu.Target>
              <Menu.Dropdown>
                {visibleItems.map((item) => {
                  const itemActive = currentPath === item.path || currentPath.startsWith(item.path + '/');
                  return (
                    <Menu.Item
                      key={item.path}
                      component={Link}
                      href={item.path}
                      leftSection={item.icon}
                      className={itemActive ? classes.menuItemActive : undefined}
                    >
                      {item.label}
                    </Menu.Item>
                  );
                })}
              </Menu.Dropdown>
            </Menu>
          );
        })}
      </Group>

      {/* Right section */}
      <Group gap="xs">
        <Text size="xs" fw={500}>
          {currentUser.name}
        </Text>
        <Menu shadow="md" width={200} position="bottom-end">
          <Menu.Target>
            <ActionIcon variant="subtle" radius="xl" size="lg">
              <Avatar size={32} color="blue" radius="xl" className={classes.avatar}>
                {getInitials(currentUser.name)}
              </Avatar>
            </ActionIcon>
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
      </Group>
    </Box>
  );
};
