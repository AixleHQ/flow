export interface NavItem {
  slug: string;
  label: string;
  badge?: string;
  children?: NavItem[];
}

export interface NavSection {
  label: string;
  items: NavItem[];
}

export const NAV_STRUCTURE: NavSection[] = [
  {
    label: 'Getting started',
    items: [
      { slug: 'what-is-aixle', label: 'What is Aixle' },
      { slug: 'quick-start', label: 'Quick start' },
      {
        slug: 'install-guide',
        label: 'Installation guide',
        children: [
          { slug: 'configuration', label: 'Configuration' },
          { slug: 'self-hosting', label: 'Self-hosting' },
          { slug: 'cli', label: 'CLI setup' },
        ],
      },
    ],
  },
  {
    label: 'Core concepts',
    items: [
      { slug: 'agents', label: 'Agents' },
      {
        slug: 'tasks-overview',
        label: 'Tasks',
        children: [
          { slug: 'tasks', label: 'Overview' },
          { slug: 'integrations', label: 'Integrations' },
          { slug: 'permissions', label: 'Permissions' },
        ],
      },
    ],
  },
  {
    label: 'Guides',
    items: [
      { slug: 'deploy', label: 'Deploy a repo', badge: 'New' },
      { slug: 'api-guide', label: 'Use the API' },
      {
        slug: 'advanced',
        label: 'Advanced',
        children: [
          { slug: 'cli-ref', label: 'CLI reference' },
          { slug: 'config-schema', label: 'Config schema' },
        ],
      },
    ],
  },
];

export function findNavItem(slug: string): NavItem | null {
  for (const section of NAV_STRUCTURE) {
    for (const item of section.items) {
      if (item.slug === slug) return item;
      if (item.children) {
        for (const child of item.children) {
          if (child.slug === slug) return child;
        }
      }
    }
  }
  return null;
}

export function findNavSection(slug: string): NavSection | null {
  for (const section of NAV_STRUCTURE) {
    for (const item of section.items) {
      if (item.slug === slug) return section;
      if (item.children) {
        for (const child of item.children) {
          if (child.slug === slug) return section;
        }
      }
    }
  }
  return null;
}

export function getPrevNext(slug: string): { prev: NavItem | null; next: NavItem | null } {
  const flat: NavItem[] = [];
  for (const section of NAV_STRUCTURE) {
    for (const item of section.items) {
      flat.push(item);
      if (item.children) flat.push(...item.children);
    }
  }
  const idx = flat.findIndex((i) => i.slug === slug);
  return {
    prev: idx > 0 ? flat[idx - 1] : null,
    next: idx < flat.length - 1 ? flat[idx + 1] : null,
  };
}
