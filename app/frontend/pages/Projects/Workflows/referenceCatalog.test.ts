import { describe, expect, it } from 'vitest';

import type { Step } from '@/types/generated';
import { buildAssetPicker } from 'test/factories/assetPicker';

import { downstreamIds, normalizeSpecName, upstreamIds } from './dataFlow';
import { availableInputs, buildReferenceCatalog } from './referenceCatalog';

type CatalogStep = Pick<Step, 'id' | 'name' | 'dependsOnStepIds' | 'assetIds' | 'mcpServerIds' | 'outputAssetSpecs'>;

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
  step({ id: 3, name: 'Report', dependsOnStepIds: [2], assetIds: [31], mcpServerIds: [7] }),
  step({ id: -4, name: 'Notes', outputAssetSpecs: [output('notes.md')] }),
];

const WORKFLOW = { baseAssetIds: [32], baseMCPServerIds: [8], inheritAllProjectResources: false };

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

const catalogFor = (sessionId: number, overrides: Partial<Parameters<typeof buildReferenceCatalog>[0]> = {}) =>
  buildReferenceCatalog({
    sessionId,
    steps: STEPS,
    workflow: WORKFLOW,
    assets: ASSETS,
    mcpServers: SERVERS,
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

  it('counts project servers as attached when the workflow inherits project resources', () => {
    const { items, bindings } = catalogFor(3, { workflow: { ...WORKFLOW, inheritAllProjectResources: true } });

    expect(items.find((item) => item.token === '{{mcp:9}}')?.hint).toBe('Project · sse');
    expect(bindings.has('{{mcp:9}}')).toBe(false);
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
