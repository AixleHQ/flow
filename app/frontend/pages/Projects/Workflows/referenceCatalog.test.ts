import { describe, expect, it } from 'vitest';

import type { Step } from '@/types/generated';
import { buildAssetPicker } from 'test/factories/assetPicker';

import { downstreamIds, normalizeSpecName, upstreamIds } from './dataFlow';
import { availableInputs, buildReferenceCatalog } from './referenceCatalog';

type CatalogStep = Pick<
  Step,
  | 'id'
  | 'name'
  | 'dependsOnStepIds'
  | 'assetIds'
  | 'mcpServerIds'
  | 'outputAssetSpecs'
  | 'toolIds'
  | 'skillIds'
  | 'configItemIds'
>;

const output = (name: string, namePattern: string | null = null) => ({
  name,
  assetType: 'file',
  required: true,
  namePattern,
});

const step = (overrides: Partial<CatalogStep> & Pick<CatalogStep, 'id' | 'name'>): CatalogStep => ({
  dependsOnStepIds: [],
  assetIds: [],
  mcpServerIds: [],
  outputAssetSpecs: [],
  toolIds: [],
  skillIds: [],
  configItemIds: [],
  ...overrides,
});

// Collect → Analyze → Report, with Notes off to the side.
const STEPS: CatalogStep[] = [
  step({
    id: 1,
    name: 'Collect',
    outputAssetSpecs: [output('raw.csv'), output('logs/*.txt'), output('x', 'report-.*')],
  }),
  step({ id: 2, name: 'Analyze', dependsOnStepIds: [1], outputAssetSpecs: [output('summary.md')] }),
  step({
    id: 3,
    name: 'Report',
    dependsOnStepIds: [2],
    assetIds: [31],
    mcpServerIds: [7],
    toolIds: [41],
    skillIds: [51],
    configItemIds: [61],
  }),
  step({ id: -4, name: 'Notes', outputAssetSpecs: [output('notes.md')] }),
];

const WORKFLOW = {
  baseAssetIds: [32],
  baseMCPServerIds: [8],
  baseToolIds: [42],
  baseSkillIds: [],
  baseConfigItemIds: [],
  inheritAllProjectResources: false,
};

const ASSETS = [
  buildAssetPicker({ id: 33, fileName: 'roadmap.docx', name: 'roadmap.docx', scope: 'company' }),
  buildAssetPicker({ id: 31, fileName: 'brand.pdf', folder: 'brand', name: 'brand/brand.pdf' }),
  buildAssetPicker({ id: 32, fileName: 'voice.md', name: 'voice.md' }),
];

const SERVERS = [
  { id: 9, name: 'Linear', transport: 'sse' as const, scope: 'project' as const },
  { id: 7, name: 'GitHub', transport: 'http' as const, scope: 'project' as const },
  { id: 8, name: 'Notion', transport: 'http' as const, scope: 'project' as const },
];

const TOOLS = [
  { id: 43, name: 'Post to Slack', toolName: 'slack_post', scope: 'project' as const },
  { id: 41, name: 'board_get_task', toolName: 'board_get_task', scope: 'system' as const },
  { id: 42, name: 'Linter', toolName: 'run_linter', scope: 'project' as const },
];

const SKILLS = [
  { id: 52, name: 'House style', skillName: 'house-style' },
  { id: 51, name: 'code-review', skillName: 'code-review' },
];

const CONFIG_ITEMS = [
  { id: 62, name: 'API_TOKEN', itemType: 'secret' as const, description: null },
  {
    id: 61,
    name: 'STAGING_URL',
    itemType: 'variable' as const,
    description: 'Base URL of the staging environment the smoke tests run against every night',
  },
];

const catalogFor = (sessionId: number, overrides: Partial<Parameters<typeof buildReferenceCatalog>[0]> = {}) =>
  buildReferenceCatalog({
    sessionId,
    steps: STEPS,
    workflow: WORKFLOW,
    assets: ASSETS,
    mcpServers: SERVERS,
    tools: TOOLS,
    skills: SKILLS,
    configItems: CONFIG_ITEMS,
    ...overrides,
  });

describe('dataFlow graph', () => {
  it('follows Run after transitively in both directions', () => {
    expect([...upstreamIds(STEPS, 3)].sort()).toEqual([1, 2]);
    expect([...downstreamIds(STEPS, 1)].sort()).toEqual([2, 3]);
    expect(upstreamIds(STEPS, -4).size).toBe(0);
  });

  it('strips the container prefix from a spec name and keeps relative paths', () => {
    expect(normalizeSpecName(' /workspace/outputs/reports/q3.md ')).toBe('reports/q3.md');
    expect(normalizeSpecName('workspace/assets/brand.pdf')).toBe('brand.pdf');
    expect(normalizeSpecName('intake/brief.md')).toBe('intake/brief.md');
  });
});

describe('buildReferenceCatalog', () => {
  it('lists attached and base assets first and binds the rest on insert', () => {
    const { items, bindings } = catalogFor(3);
    const assets = items.filter((item) => item.kind === 'asset');

    expect(assets.map((a) => [a.label, a.hint])).toEqual([
      ['brand.pdf', 'brand · Attached'],
      ['voice.md', 'Workflow base'],
      ['roadmap.docx', 'Company asset — attaches on insert'],
    ]);
    expect(bindings.get('{{asset:33}}')).toEqual({ kind: 'attach_asset', assetId: 33 });
    expect(bindings.has('{{asset:31}}')).toBe(false);
    expect(bindings.has('{{asset:32}}')).toBe(false);
  });

  it('offers other sessions’ plain outputs, upstream ones as they are and others with a Run after binding', () => {
    const { items, bindings } = catalogFor(3);
    const outputs = items.filter((item) => item.kind === 'output');

    expect(outputs.map((o) => [o.token, o.hint])).toEqual([
      ['{{output:1:raw.csv}}', 'Output of Collect'],
      ['{{output:2:summary.md}}', 'Output of Analyze'],
      ['{{output:new-4:notes.md}}', 'Output of Notes — adds Run after'],
    ]);
    expect(bindings.get('{{output:new-4:notes.md}}')).toEqual({ kind: 'add_dependency', stepKey: 'new-4' });
    expect(bindings.has('{{output:1:raw.csv}}')).toBe(false);
  });

  it("disables a downstream session's outputs and lists the session's own as where to write", () => {
    const { items, bindings } = catalogFor(1);
    const outputs = items.filter((item) => item.kind === 'output');

    const own = outputs.find((o) => o.token === '{{output:1:raw.csv}}');
    expect(own?.hint).toBe('Output of this session');
    expect(own?.disabledReason).toBeUndefined();
    expect(outputs.find((o) => o.token === '{{output:2:summary.md}}')?.disabledReason).toBe(
      'Output of Analyze, which runs after this session',
    );
    expect(bindings.has('{{output:2:summary.md}}')).toBe(false);
  });

  it('lists every other session with how it relates to this one', () => {
    const sessions = catalogFor(2).items.filter((item) => item.kind === 'step');

    expect(sessions.map((s) => [s.token, s.label, s.hint])).toEqual([
      ['{{step:1}}', 'Collect', 'Session 1 · runs before'],
      ['{{step:3}}', 'Report', 'Session 3 · runs after this session'],
      ['{{step:new-4}}', 'Notes', 'Session 4 · not upstream'],
    ]);
  });

  it('shows where each MCP server comes from and binds the unattached ones', () => {
    const { items, bindings } = catalogFor(3);
    const servers = items.filter((item) => item.kind === 'mcp');

    expect(servers.map((s) => [s.label, s.hint])).toEqual([
      ['GitHub', 'Session · http'],
      ['Notion', 'Workflow base · http'],
      ['Linear', 'Not attached — attaches on insert · sse'],
    ]);
    expect(bindings.get('{{mcp:9}}')).toEqual({ kind: 'attach_mcp_server', mcpServerId: 9 });
  });

  it('counts every server as attached when the workflow inherits project resources, internal ones included', () => {
    const internal = { id: 10, name: 'aixle-tools', transport: 'http' as const, scope: 'internal' as const };
    const { items, bindings } = catalogFor(3, {
      workflow: { ...WORKFLOW, inheritAllProjectResources: true },
      mcpServers: [...SERVERS, internal],
    });

    expect(items.find((item) => item.token === '{{mcp:9}}')?.hint).toBe('Project · sse');
    expect(items.find((item) => item.token === '{{mcp:10}}')?.hint).toBe('Project · http');
    expect(bindings.has('{{mcp:9}}')).toBe(false);
    expect(bindings.has('{{mcp:10}}')).toBe(false);
  });

  it('lists tools, skills and config items in their own groups, after the connections', () => {
    const { items } = catalogFor(3);
    const groups = items.map((item) => item.group).filter((group, i, all) => all.indexOf(group) === i);

    expect(groups).toEqual(['Assets', 'Sessions', 'Connections', 'Tools', 'Skills', 'Config items']);
  });

  it('shows where each tool and skill comes from, the name the agent calls it by, and binds the unattached', () => {
    const { items, bindings } = catalogFor(3);

    expect(items.filter((item) => item.kind === 'tool').map((t) => [t.label, t.hint])).toEqual([
      ['board_get_task', 'Session'],
      ['Linter', 'run_linter · Workflow base'],
      ['Post to Slack', 'slack_post · Not attached — attaches on insert'],
    ]);
    expect(items.filter((item) => item.kind === 'skill').map((sk) => [sk.label, sk.hint])).toEqual([
      ['code-review', 'Session'],
      ['House style', 'house-style · Not attached — attaches on insert'],
    ]);
    expect(bindings.get('{{tool:43}}')).toEqual({ kind: 'attach_tool', toolId: 43 });
    expect(bindings.get('{{skill:52}}')).toEqual({ kind: 'attach_skill', skillId: 52 });
    expect(bindings.has('{{tool:41}}')).toBe(false);
    expect(bindings.has('{{tool:42}}')).toBe(false);
  });

  it('labels a config item a secret or a variable, never shows a value, and binds the unattached', () => {
    const { items, bindings } = catalogFor(3);

    expect(items.filter((item) => item.kind === 'config_item').map((c) => [c.label, c.hint])).toEqual([
      ['STAGING_URL', 'Variable · Session · Base URL of the staging environment the smoke tests run aga…'],
      ['API_TOKEN', 'Secret · Not attached — attaches on insert'],
    ]);
    expect(bindings.get('{{config_item:62}}')).toEqual({ kind: 'attach_config_item', configItemId: 62 });
  });

  it('counts every tool, skill and config item as attached when the workflow inherits project resources', () => {
    const { bindings } = catalogFor(3, { workflow: { ...WORKFLOW, inheritAllProjectResources: true } });

    expect(
      [...bindings.values()].filter((fix) => fix.kind !== 'attach_asset' && fix.kind !== 'add_dependency'),
    ).toEqual([]);
  });
});

describe('availableInputs', () => {
  it('lists upstream outputs, transitive ones included, then base and attached assets', () => {
    expect(availableInputs({ sessionId: 3, steps: STEPS, workflow: WORKFLOW, assets: ASSETS })).toEqual([
      { name: 'raw.csv', source: 'Collect' },
      { name: 'logs/*.txt', source: 'Collect' },
      { name: 'matching report-.*', source: 'Collect' },
      { name: 'summary.md', source: 'Analyze' },
      { name: 'voice.md', source: 'Workflow base' },
      { name: 'brand/brand.pdf', source: 'Attached' },
    ]);
  });
});
