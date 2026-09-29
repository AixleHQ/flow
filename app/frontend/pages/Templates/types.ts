export type TemplateKind = 'project' | 'workflow' | 'board' | 'agent' | 'skill' | 'connector';

export interface TemplateRequires {
  integrations: string[];
  repositories: { key: string; purpose?: string }[];
  secrets: { name: string; description?: string; promptAtInstall?: boolean }[];
}

export interface TemplatePublisher {
  name: string;
  displayName: string;
  url: string | null;
  verified: boolean;
}

export interface TemplateSummary {
  identifier: string;
  namespace: string;
  slug: string;
  publisher: TemplatePublisher;
  name: string;
  summary: string | null;
  kind: TemplateKind;
  version: number;
  commitSha: string;
  categories: string[];
  installCount: number;
  requires: TemplateRequires;
  includes: Record<string, number>;
}

export interface TemplateInput {
  key: string;
  label: string;
  description?: string;
  type: 'string' | 'text' | 'select' | 'boolean';
  options?: string[];
  default?: string | boolean;
  required?: boolean;
}

export interface TemplateContents {
  agents: string[];
  skills: { name: string; fromRegistry: boolean }[];
  tools: { name: string; platform: boolean; image?: string }[];
  mcpServers: { name: string; connector: boolean; builtIn: boolean }[];
  assets: string[];
  workflows: { name: string; steps: string[] }[];
  triggers: { kind: string; workflow: string; column?: string; cron?: string }[];
  variables: string[];
}

export interface TemplateDetail extends TemplateSummary {
  readme: string | null;
  setup: string | null;
  inputs: TemplateInput[];
  contents: TemplateContents;
  boardColumns: string[];
  revoked: boolean;
  revocationReason: string | null;
  runsThirdPartyImages: boolean;
}

export const KIND_LABELS: Record<TemplateKind, string> = {
  project: 'Project',
  workflow: 'Workflow',
  board: 'Board',
  agent: 'Agent',
  skill: 'Skill',
  connector: 'Connector',
};

export const KIND_COLORS: Record<TemplateKind, string> = {
  project: 'brand',
  workflow: 'blue',
  board: 'violet',
  agent: 'orange',
  skill: 'yellow',
  connector: 'teal',
};

const INCLUDE_LABELS: Record<string, [string, string]> = {
  columns: ['column', 'columns'],
  agents: ['agent', 'agents'],
  workflows: ['workflow', 'workflows'],
  steps: ['step', 'steps'],
  skills: ['skill', 'skills'],
  tools: ['tool', 'tools'],
  mcpServers: ['MCP server', 'MCP servers'],
  assets: ['asset', 'assets'],
  triggers: ['trigger', 'triggers'],
};

export const templatePath = (t: { namespace: string; slug: string }) => `/templates/${t.namespace}/${t.slug}`;

/** "7 columns · 3 agents · 2 workflows" from a template's section counts. */
export function describeIncludes(includes: Record<string, number>): string {
  return Object.entries(INCLUDE_LABELS)
    .filter(([key]) => (includes[key] ?? 0) > 0)
    .map(([key, [one, many]]) => `${includes[key]} ${includes[key] === 1 ? one : many}`)
    .join(' · ');
}
