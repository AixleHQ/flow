import type { AssetPicker, MCPServerPicker, Step, Workflow } from '@/types/generated';

import type { ReferenceItem } from 'shared/components/ReferenceEditor/ReferenceEditor';
import { referenceToken } from 'shared/lib/references';

import { stepKey } from './builderDraft';
import { downstreamIds, type IssueFix, isPlainSpecName, sessionLabel, upstreamIds } from './dataFlow';

export const REFERENCE_GROUPS = ['Assets', 'Sessions', 'Connections'] as const;

type CatalogStep = Pick<Step, 'id' | 'name' | 'dependsOnStepIds' | 'assetIds' | 'mcpServerIds' | 'outputAssetSpecs'>;
type CatalogWorkflow = Pick<Workflow, 'baseAssetIds' | 'baseMCPServerIds' | 'inheritAllProjectResources'>;
// Older servers send `{ id, name }` only; the extra fields only refine hints.
type CatalogAsset = Pick<AssetPicker, 'id' | 'name'> & Partial<Pick<AssetPicker, 'fileName' | 'folder' | 'scope'>>;
type CatalogServer = Pick<MCPServerPicker, 'id' | 'name'> & Partial<Pick<MCPServerPicker, 'transport' | 'scope'>>;

export interface ReferenceCatalogInput {
  sessionId: number;
  /** Every session, in tree order. */
  steps: CatalogStep[];
  workflow: CatalogWorkflow;
  assets: CatalogAsset[];
  mcpServers: CatalogServer[];
}

export interface ReferenceCatalogResult {
  items: ReferenceItem[];
  /** What inserting a token also has to change for the reference to work at run time. */
  bindings: Map<string, IssueFix>;
}

const join = (...parts: (string | null | undefined | false)[]) => parts.filter(Boolean).join(' · ');

/** The `@` picker for one session: what it can name, how each row reads, and what picking it binds. */
export function buildReferenceCatalog({
  sessionId,
  steps,
  workflow,
  assets,
  mcpServers,
}: ReferenceCatalogInput): ReferenceCatalogResult {
  const session = steps.find((s) => s.id === sessionId);
  const items: ReferenceItem[] = [];
  const bindings = new Map<string, IssueFix>();
  if (!session) return { items, bindings };

  const upstream = upstreamIds(steps, sessionId);
  const downstream = downstreamIds(steps, sessionId);
  const number = (id: number) => steps.findIndex((s) => s.id === id) + 1;

  // Assets: what the session already receives first, then the rest of the project's.
  const attached = new Set(session.assetIds);
  const base = new Set(workflow.baseAssetIds);
  const assetRank = (a: CatalogAsset) => (attached.has(a.id) ? 0 : base.has(a.id) ? 1 : 2);
  for (const asset of [...assets].sort((a, b) => assetRank(a) - assetRank(b))) {
    const token = referenceToken.asset(asset.id);
    const state = attached.has(asset.id)
      ? 'Attached'
      : base.has(asset.id)
        ? 'Workflow base'
        : `${asset.scope === 'company' ? 'Company' : 'Project'} asset — attaches on insert`;
    items.push({
      token,
      kind: 'asset',
      label: asset.fileName ?? asset.name,
      hint: join(asset.folder, state),
      group: 'Assets',
    });
    if (!attached.has(asset.id) && !base.has(asset.id))
      bindings.set(token, { kind: 'attach_asset', assetId: asset.id });
  }

  // Declared outputs: this session's own (where to write), then other sessions' (what to read).
  const plainOutputs = (step: CatalogStep) =>
    (step.outputAssetSpecs ?? []).filter((spec) => !spec.namePattern && isPlainSpecName(spec.name));
  for (const spec of plainOutputs(session)) {
    items.push({
      token: referenceToken.output(stepKey(session.id), spec.name),
      kind: 'output',
      label: spec.name,
      hint: 'Output of this session',
      group: 'Assets',
    });
  }
  for (const step of steps) {
    if (step.id === sessionId) continue;
    const producer = sessionLabel(steps, step.id);
    for (const spec of plainOutputs(step)) {
      const token = referenceToken.output(stepKey(step.id), spec.name);
      const isUpstream = upstream.has(step.id);
      items.push({
        token,
        kind: 'output',
        label: spec.name,
        hint: `Output of ${producer}${isUpstream ? '' : ' — adds Run after'}`,
        group: 'Assets',
        disabledReason: downstream.has(step.id) ? `Output of ${producer}, which runs after this session` : undefined,
      });
      if (!isUpstream && !downstream.has(step.id))
        bindings.set(token, { kind: 'add_dependency', stepKey: stepKey(step.id) });
    }
  }

  for (const step of steps) {
    if (step.id === sessionId) continue;
    const relation = upstream.has(step.id)
      ? 'runs before'
      : downstream.has(step.id)
        ? 'runs after this session'
        : 'not upstream';
    items.push({
      token: referenceToken.step(stepKey(step.id)),
      kind: 'step',
      label: sessionLabel(steps, step.id),
      hint: join(`Session ${number(step.id)}`, relation),
      group: 'Sessions',
    });
  }

  const sessionServers = new Set(session.mcpServerIds);
  const baseServers = new Set(workflow.baseMCPServerIds);
  const source = (server: CatalogServer) => {
    if (sessionServers.has(server.id)) return 'Session';
    if (baseServers.has(server.id)) return 'Workflow base';
    if (workflow.inheritAllProjectResources && server.scope === 'project') return 'Project';
    return null;
  };
  const serverRank = (server: CatalogServer) => (source(server) ? 0 : 1);
  for (const server of [...mcpServers].sort((a, b) => serverRank(a) - serverRank(b))) {
    const token = referenceToken.mcp(server.id);
    const from = source(server);
    items.push({
      token,
      kind: 'mcp',
      label: server.name,
      hint: join(from ?? 'Not attached — attaches on insert', server.transport),
      group: 'Connections',
    });
    if (!from) bindings.set(token, { kind: 'attach_mcp_server', mcpServerId: server.id });
  }

  return { items, bindings };
}

export interface AvailableInput {
  name: string;
  source: string;
}

/** Files a session can count on when it starts: upstream sessions' declared outputs and its assets. */
export function availableInputs({
  sessionId,
  steps,
  workflow,
  assets,
}: Omit<ReferenceCatalogInput, 'mcpServers'>): AvailableInput[] {
  const session = steps.find((s) => s.id === sessionId);
  if (!session) return [];
  const upstream = upstreamIds(steps, sessionId);
  const byId = new Map(assets.map((a) => [a.id, a]));
  const fromSessions = steps
    .filter((s) => upstream.has(s.id))
    .flatMap((s) =>
      (s.outputAssetSpecs ?? [])
        .filter((spec) => spec.name.trim() !== '' || spec.namePattern)
        .map((spec) => ({
          name: spec.namePattern ? `matching ${spec.namePattern}` : spec.name,
          source: sessionLabel(steps, s.id),
        })),
    );
  const fromAssets = (ids: number[], source: string) =>
    ids.flatMap((id) => {
      const asset = byId.get(id);
      return asset ? [{ name: asset.name, source }] : [];
    });
  return [
    ...fromSessions,
    ...fromAssets(workflow.baseAssetIds, 'Workflow base'),
    ...fromAssets(
      session.assetIds.filter((id) => !workflow.baseAssetIds.includes(id)),
      'Attached',
    ),
  ];
}
