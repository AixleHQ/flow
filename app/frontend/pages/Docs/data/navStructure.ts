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
    label: 'User guide',
    items: [
      { slug: 'user-guide', label: 'Overview' },
      { slug: 'quick-start', label: 'Quick start' },
      { slug: 'agents', label: 'Agents' },
      { slug: 'runtimes', label: 'Runtimes' },
      { slug: 'tools', label: 'Tools' },
      { slug: 'mcp', label: 'MCP servers' },
      { slug: 'board', label: 'Board' },
      { slug: 'workflows', label: 'Workflows' },
      { slug: 'triggers-and-gates', label: 'Triggers and gates' },
      { slug: 'integrations', label: 'Integrations' },
      { slug: 'configuration', label: 'Configuration' },
    ],
  },
  {
    label: 'Reference',
    items: [
      { slug: 'reference', label: 'Overview' },
      { slug: 'cli-ref', label: 'CLI reference' },
      { slug: 'api-guide', label: 'API' },
      { slug: 'config-schema', label: 'Configuration reference' },
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
