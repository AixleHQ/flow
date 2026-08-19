export interface SearchResult {
  slug: string;
  title: string;
  section: string;
  desc: string;
}

export const SEARCH_INDEX: SearchResult[] = [
  {
    slug: 'using-flow',
    title: 'What Flow is',
    section: 'Using Flow',
    desc: 'What Aixle Flow does for a team: the board → workflow → agent loop, the company/project/profile levels, and the supported agent runtimes.',
  },
  {
    slug: 'getting-started',
    title: 'Getting started',
    section: 'Using Flow',
    desc: 'From an invitation to a running workflow: onboarding, connecting an agent, and the Account, Usage and MCP tabs of your profile.',
  },
  {
    slug: 'project-home',
    title: 'Project home & settings',
    section: 'Using Flow',
    desc: 'The Overview page KPIs, run donut and task distribution, plus project name, artifacts language, archive and delete.',
  },
  {
    slug: 'tasks',
    title: 'Tasks & the board',
    section: 'Using Flow',
    desc: 'Columns and their purpose, board templates, cards and their tabs, filters and view presets, and binding a column to a workflow.',
  },
  {
    slug: 'running-workflows',
    title: 'Building workflows',
    section: 'Using Flow',
    desc: 'Creating a workflow, what a step holds, dependencies and parallel steps, on-failure behaviour, approval steps, and publishing to the catalog.',
  },
  {
    slug: 'starting-work',
    title: 'Triggers & gates',
    section: 'Using Flow',
    desc: 'The four ways a workflow starts — column, schedule, Slack, incoming webhook — and CI gates: waiting, passed, failed, stale.',
  },
  {
    slug: 'sessions-and-runs',
    title: 'Sessions & Runs',
    section: 'Using Flow',
    desc: 'The unified list of runs and agent sessions, the live step terminal, approve, retry, skip and cancel, and reviewing what a run produced.',
  },
  {
    slug: 'assets',
    title: 'Assets',
    section: 'Using Flow',
    desc: 'Uploading files for agents, promoting what a run produced into the project, search and version history.',
  },
  {
    slug: 'personas',
    title: 'Agent personas',
    section: 'Using Flow',
    desc: 'Reusable agent personas: what they define, why they are independent of the runtime, and how steps reference them.',
  },
  {
    slug: 'agent-capabilities',
    title: 'Wrappers, Skills & Connectors',
    section: 'Using Flow',
    desc: 'The three ways to extend an agent: wrappers you write, skills as packaged know-how, and connectors to external tool servers.',
  },
  {
    slug: 'repositories',
    title: 'Repositories & Integrations',
    section: 'Using Flow',
    desc: 'Linking the Git repositories agents work in, connecting the accounts a project needs, and what that lets a run do.',
  },
  {
    slug: 'ai-builder',
    title: 'AI Builder',
    section: 'Using Flow',
    desc: 'Describe a process in plain language and let the builder create the board columns, workflows and steps, then adjust them by hand.',
  },
  {
    slug: 'people-and-access',
    title: 'Team & access',
    section: 'Using Flow',
    desc: 'Admin, employee and viewer roles, company members, project collaborators, and what each role can see.',
  },
  {
    slug: 'secrets',
    title: 'Secrets & Variables',
    section: 'Using Flow',
    desc: 'Credentials and configuration a run needs, kept out of prompts, task text and logs.',
  },
  {
    slug: 'analytics',
    title: 'Analytics & cost',
    section: 'Using Flow',
    desc: 'Spend, tokens, sessions and success by project, agent, workflow and source — and where cost shows up elsewhere.',
  },
  {
    slug: 'company-workspace',
    title: 'Company workspace',
    section: 'Using Flow',
    desc: 'Projects, the Workflow Catalog, company-wide analytics and sessions, company assets and members, and switching companies.',
  },
  {
    slug: 'examples',
    title: 'Worked examples',
    section: 'Using Flow',
    desc: 'Two end-to-end stories: a card that comes back as a pull request, and a workflow built from a single prompt.',
  },
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
];

export function searchDocs(query: string): SearchResult[] {
  const q = query.toLowerCase().trim();
  if (!q) return [];
  return SEARCH_INDEX.filter(
    (r) => r.title.toLowerCase().includes(q) || r.desc.toLowerCase().includes(q) || r.section.toLowerCase().includes(q),
  );
}
