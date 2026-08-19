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
  // The product guide comes first: most readers arrive wanting to use Flow, not to
  // install it. The operator sections below keep their slugs so existing links hold.
  {
    label: 'Using Flow',
    items: [
      { slug: 'using-flow', label: 'What Flow is' },
      { slug: 'getting-started', label: 'Getting started' },
      { slug: 'project-home', label: 'Project home & settings' },
      { slug: 'tasks', label: 'Tasks & the board' },
      { slug: 'running-workflows', label: 'Building workflows' },
      { slug: 'starting-work', label: 'Triggers & gates' },
      { slug: 'sessions-and-runs', label: 'Sessions & Runs' },
      { slug: 'assets', label: 'Assets' },
      { slug: 'personas', label: 'Agent personas' },
      { slug: 'agent-capabilities', label: 'Wrappers, Skills & Connectors' },
      { slug: 'repositories', label: 'Repositories & Integrations' },
      { slug: 'ai-builder', label: 'AI Builder' },
      { slug: 'people-and-access', label: 'Team & access' },
      { slug: 'secrets', label: 'Secrets & Variables' },
      { slug: 'analytics', label: 'Analytics & cost' },
      { slug: 'company-workspace', label: 'Company workspace' },
      { slug: 'examples', label: 'Worked examples' },
    ],
  },
  {
    label: 'User guide',
    items: [
      { slug: 'user-guide', label: 'Overview' },
      { slug: 'quick-start', label: 'Quick start' },
      { slug: 'agents', label: 'Agents' },
      { slug: 'runtimes', label: 'Runtimes' },
      { slug: 'tools', label: 'Tools' },
      // The app nav calls this page's subject "Connectors"; same thing, and
      // naming both is what lets a docs reader find it in the product. NOT done
      // for Tools above: "Wrappers" in the nav is only the tools you author
      // yourself, so the two are not interchangeable.
      { slug: 'mcp', label: 'MCP servers (Connectors)' },
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
