export interface SearchResult {
  slug: string;
  title: string;
  section: string;
  desc: string;
}

export const SEARCH_INDEX: SearchResult[] = [
  {
    slug: 'user-guide',
    title: 'User Guide',
    section: 'User guide',
    desc: 'Overview of Aixle Flow: the mental model, how the board, workflows, and agents fit together.',
  },
  {
    slug: 'quick-start',
    title: 'Quick start',
    section: 'User guide',
    desc: 'Get a working Aixle Flow instance running with Docker in 10–15 minutes.',
  },
  {
    slug: 'agents',
    title: 'Agents',
    section: 'User guide',
    desc: 'An agent is a persona (system prompt) running on an LLM CLI runtime inside a Docker container.',
  },
  {
    slug: 'runtimes',
    title: 'Runtimes',
    section: 'User guide',
    desc: 'The five LLM CLI runtimes: claude_code, cursor_cli, codex, gemini_cli, and grok.',
  },
  {
    slug: 'tools',
    title: 'Tools',
    section: 'User guide',
    desc: 'Tools are callables agents invoke via MCP — board tools, custom container tools, and built-in lifecycle tools.',
  },
  {
    slug: 'mcp',
    title: 'MCP servers',
    section: 'User guide',
    desc: 'MCP servers deliver tools to agents. The internal aixle-tools server is always connected.',
  },
  {
    slug: 'board',
    title: 'Board',
    section: 'User guide',
    desc: 'A Kanban board with column → workflow bindings that trigger agent runs when cards move.',
  },
  {
    slug: 'workflows',
    title: 'Workflows',
    section: 'User guide',
    desc: 'A DAG of steps orchestrated by Temporal — each step is one agent session in one container.',
  },
  {
    slug: 'triggers-and-gates',
    title: 'Triggers and Gates',
    section: 'User guide',
    desc: 'How workflows start and pause: triggers (column, manual, schedule, Slack, webhook) vs gates (CI checks); subject_policy; the webhook start API.',
  },
  {
    slug: 'integrations',
    title: 'Integrations',
    section: 'User guide',
    desc: 'Connect Aixle Flow with GitHub, GitLab, Linear, Coder, and Slack.',
  },
  {
    slug: 'configuration',
    title: 'Configuration',
    section: 'User guide',
    desc: 'Configure Aixle Flow at three levels: environment variables, Config Items, and per-user Profile.',
  },
  {
    slug: 'reference',
    title: 'Reference',
    section: 'Reference',
    desc: 'Complete surface area: CLI, API, configuration. Includes the full domain model schema.',
  },
  {
    slug: 'cli-ref',
    title: 'CLI reference',
    section: 'Reference',
    desc: 'Complete reference for all Makefile targets: lifecycle, database, linting, images.',
  },
  {
    slug: 'api-guide',
    title: 'API',
    section: 'Reference',
    desc: 'REST API under /api/v1 — workflows, workflow runs, board, tasks, assets, and webhooks.',
  },
  {
    slug: 'config-schema',
    title: 'Configuration reference',
    section: 'Reference',
    desc: 'Every environment variable Aixle Flow reads, organized by subsystem.',
  },
  {
    slug: 'user-guide-outline',
    title: 'User guide outline',
    section: 'Product',
    desc: 'The chapter-by-chapter skeleton of the end-user product guide, following the product sidebar.',
  },
  {
    slug: 'changelog-product-areas',
    title: 'Changelog product areas',
    section: 'Product',
    desc: 'The product-area taxonomy every user-visible changelog entry is tagged with.',
  },
];

export function searchDocs(query: string): SearchResult[] {
  const q = query.toLowerCase().trim();
  if (!q) return [];
  return SEARCH_INDEX.filter(
    (r) => r.title.toLowerCase().includes(q) || r.desc.toLowerCase().includes(q) || r.section.toLowerCase().includes(q),
  );
}
