export interface SearchResult {
  slug: string;
  title: string;
  section: string;
  desc: string;
}

export const SEARCH_INDEX: SearchResult[] = [
  {
    slug: 'what-is-aixle',
    title: 'What is Aixle',
    section: 'Getting started',
    desc: 'Aixle is an AI agent orchestration platform for automating engineering workflows.',
  },
  {
    slug: 'quick-start',
    title: 'Quick start',
    section: 'Getting started',
    desc: 'Get up and running with Aixle in under 5 minutes.',
  },
  {
    slug: 'configuration',
    title: 'Configuration',
    section: 'Getting started',
    desc: 'Configure your Aixle installation using environment variables and config files.',
  },
  {
    slug: 'self-hosting',
    title: 'Self-hosting',
    section: 'Getting started',
    desc: 'Deploy Aixle on your own infrastructure using Docker or Kubernetes.',
  },
  {
    slug: 'cli',
    title: 'CLI setup',
    section: 'Getting started',
    desc: 'Install and configure the Aixle CLI for interacting with your workspace.',
  },
  {
    slug: 'agents',
    title: 'Agents',
    section: 'Core concepts',
    desc: 'Agents are autonomous AI workers that execute tasks in your repositories.',
  },
  {
    slug: 'tasks',
    title: 'Tasks overview',
    section: 'Core concepts',
    desc: 'Tasks represent units of work assigned to agents within a board workflow.',
  },
  {
    slug: 'integrations',
    title: 'Integrations',
    section: 'Core concepts',
    desc: 'Connect Aixle with GitHub, GitLab, Slack, and other external services.',
  },
  {
    slug: 'permissions',
    title: 'Permissions',
    section: 'Core concepts',
    desc: 'Control what agents and team members can access within your projects.',
  },
  {
    slug: 'deploy',
    title: 'Deploy a repo',
    section: 'Guides',
    desc: 'Use Aixle to automate deployment pipelines for your repositories.',
  },
  {
    slug: 'api-guide',
    title: 'Use the API',
    section: 'Guides',
    desc: 'Interact with Aixle programmatically via the REST API.',
  },
  {
    slug: 'cli-ref',
    title: 'CLI reference',
    section: 'Guides',
    desc: 'Complete reference for all Aixle CLI commands and flags.',
  },
  {
    slug: 'config-schema',
    title: 'Config schema',
    section: 'Guides',
    desc: 'Full JSON schema reference for the Aixle configuration file.',
  },
];

export function searchDocs(query: string): SearchResult[] {
  const q = query.toLowerCase().trim();
  if (!q) return [];
  return SEARCH_INDEX.filter(
    (r) => r.title.toLowerCase().includes(q) || r.desc.toLowerCase().includes(q) || r.section.toLowerCase().includes(q),
  );
}
