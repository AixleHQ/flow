import type { TemplateDetail, TemplateSummary } from 'pages/Templates/types';

export const buildTemplateSummary = (overrides: Partial<TemplateSummary> = {}): TemplateSummary => ({
  identifier: 'acme/dev-team-sdlc',
  namespace: 'acme',
  slug: 'dev-team-sdlc',
  publisher: { name: 'acme', displayName: 'Acme Corp', url: null, verified: false },
  name: 'Dev team SDLC',
  summary: 'Board, agents and a delivery workflow for a code repository.',
  kind: 'project',
  version: 3,
  commitSha: 'a'.repeat(40),
  categories: ['engineering'],
  installCount: 12,
  requires: { integrations: ['github'], repositories: [{ key: 'app_repo' }], secrets: [{ name: 'SENTRY_TOKEN' }] },
  includes: { columns: 4, agents: 1, workflows: 1, steps: 2 },
  ...overrides,
});

export const buildTemplateDetail = (overrides: Partial<TemplateDetail> = {}): TemplateDetail => ({
  ...buildTemplateSummary(),
  readme: '# Dev team SDLC',
  setup: 'Connect GitHub first.',
  inputs: [{ key: 'default_branch', label: 'Default branch', type: 'string', default: 'main' }],
  contents: {
    agents: ['architect'],
    skills: [{ name: 'code-review', fromRegistry: true }],
    tools: [{ name: 'run_tests', platform: false, image: 'ghcr.io/acme/runner@sha256:aaa' }],
    mcpServers: [{ name: 'Sentry', connector: false, builtIn: false }],
    assets: [],
    workflows: [{ name: 'Delivery', steps: ['Tech design', 'Implement'] }],
    triggers: [{ kind: 'column', workflow: 'delivery', column: 'design' }],
    variables: ['SENTRY_ORG'],
  },
  boardColumns: ['Backlog', 'Tech Design', 'Done'],
  revoked: false,
  revocationReason: null,
  runsThirdPartyImages: true,
  ...overrides,
});
