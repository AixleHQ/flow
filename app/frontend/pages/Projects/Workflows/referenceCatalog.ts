import type {
  AssetPicker,
  ConfigItemPicker,
  MCPServerPicker,
  SkillPicker,
  Step,
  ToolPicker,
  Workflow,
} from '@/types/generated';

import type { ReferenceItem } from 'shared/components/ReferenceEditor/ReferenceEditor';
import { referenceToken } from 'shared/lib/references';

import { stepKey } from './builderDraft';
import { downstreamIds, type IssueFix, isPlainSpecName, sessionLabel, upstreamIds } from './dataFlow';

export const REFERENCE_GROUPS = ['Assets', 'Sessions', 'Connections', 'Tools', 'Skills', 'Config items'] as const;

type CatalogStep = Pick<Step, 'id' | 'name' | 'dependsOnStepIds' | 'assetIds' | 'mcpServerIds' | 'outputAssetSpecs'> &
  Partial<Pick<Step, 'toolIds' | 'skillIds' | 'configItemIds'>>;
type CatalogWorkflow = Pick<Workflow, 'baseAssetIds' | 'baseMCPServerIds' | 'inheritAllProjectResources'> &
  Partial<Pick<Workflow, 'baseToolIds' | 'baseSkillIds' | 'baseConfigItemIds'>>;
// Older servers send `{ id, name }` only; the extra fields only refine hints.
type CatalogAsset = Pick<AssetPicker, 'id' | 'name'> & Partial<Pick<AssetPicker, 'fileName' | 'folder' | 'scope'>>;
type CatalogServer = Pick<MCPServerPicker, 'id' | 'name'> & Partial<Pick<MCPServerPicker, 'transport' | 'scope'>>;
type CatalogTool = Pick<ToolPicker, 'id' | 'name'> & Partial<Pick<ToolPicker, 'toolName' | 'scope'>>;
type CatalogSkill = Pick<SkillPicker, 'id' | 'name'> & Partial<Pick<SkillPicker, 'skillName'>>;
// The server sends a missing description as null, which the generated optional type does not admit.
type CatalogConfigItem = Pick<ConfigItemPicker, 'id' | 'name'> &
  Partial<Pick<ConfigItemPicker, 'itemType'>> & { description?: string | null };

export interface ReferenceCatalogInput {
  sessionId: number;
  /** Every session, in tree order. */
  steps: CatalogStep[];
  workflow: CatalogWorkflow;
  assets: CatalogAsset[];
  mcpServers: CatalogServer[];
  tools?: CatalogTool[];
  skills?: CatalogSkill[];
  configItems?: CatalogConfigItem[];
}

export interface ReferenceCatalogResult {
  items: ReferenceItem[];
  /** What inserting a token also has to change for the reference to work at run time. */
  bindings: Map<string, IssueFix>;
}

const join = (...parts: (string | null | undefined | false)[]) => parts.filter(Boolean).join(' · ');

const NOT_ATTACHED = 'Not attached — attaches on insert';

const truncate = (text: string | null | undefined, max = 60) =>
  text && text.length > max ? `${text.slice(0, max - 1).trimEnd()}…` : text;

/** The `@` picker for one session: what it can name, how each row reads, and what picking it binds. */
export function buildReferenceCatalog({
  sessionId,
  steps,
  workflow,
  assets,
  mcpServers,
  tools = [],
  skills = [],
  configItems = [],
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

  // Where a session gets a resource from — its own list, the workflow base, or (when the workflow
  // inherits) everything the project offers, which is what each picker prop already lists.
  const sourceOf = (sessionIds: number[] | undefined, baseIds: number[] | undefined) => {
    const own = new Set(sessionIds ?? []);
    const base = new Set(baseIds ?? []);
    return (id: number) => {
      if (own.has(id)) return 'Session';
      if (base.has(id)) return 'Workflow base';
      if (workflow.inheritAllProjectResources) return 'Project';
      return null;
    };
  };
  const attachedFirst = <T extends { id: number }>(list: T[], source: (id: number) => string | null) =>
    [...list].sort((a, b) => (source(a.id) ? 0 : 1) - (source(b.id) ? 0 : 1));

  const serverSource = sourceOf(session.mcpServerIds, workflow.baseMCPServerIds);
  for (const server of attachedFirst(mcpServers, serverSource)) {
    const token = referenceToken.mcp(server.id);
    const from = serverSource(server.id);
    items.push({
      token,
      kind: 'mcp',
      label: server.name,
      hint: join(from ?? NOT_ATTACHED, server.transport),
      group: 'Connections',
    });
    if (!from) bindings.set(token, { kind: 'attach_mcp_server', mcpServerId: server.id });
  }

  const toolSource = sourceOf(session.toolIds, workflow.baseToolIds);
  for (const tool of attachedFirst(tools, toolSource)) {
    const token = referenceToken.tool(tool.id);
    const from = toolSource(tool.id);
    items.push({
      token,
      kind: 'tool',
      label: tool.name,
      hint: join(tool.toolName !== tool.name && tool.toolName, from ?? NOT_ATTACHED),
      group: 'Tools',
    });
    if (!from) bindings.set(token, { kind: 'attach_tool', toolId: tool.id });
  }

  const skillSource = sourceOf(session.skillIds, workflow.baseSkillIds);
  for (const skill of attachedFirst(skills, skillSource)) {
    const token = referenceToken.skill(skill.id);
    const from = skillSource(skill.id);
    items.push({
      token,
      kind: 'skill',
      label: skill.name,
      hint: join(skill.skillName !== skill.name && skill.skillName, from ?? NOT_ATTACHED),
      group: 'Skills',
    });
    if (!from) bindings.set(token, { kind: 'attach_skill', skillId: skill.id });
  }

  const configSource = sourceOf(session.configItemIds, workflow.baseConfigItemIds);
  for (const configItem of attachedFirst(configItems, configSource)) {
    const token = referenceToken.configItem(configItem.id);
    const from = configSource(configItem.id);
    items.push({
      token,
      kind: 'config_item',
      label: configItem.name,
      hint: join(
        configItem.itemType && (configItem.itemType === 'secret' ? 'Secret' : 'Variable'),
        from ?? NOT_ATTACHED,
        truncate(configItem.description),
      ),
      group: 'Config items',
    });
    if (!from) bindings.set(token, { kind: 'attach_config_item', configItemId: configItem.id });
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
}: Pick<ReferenceCatalogInput, 'sessionId' | 'steps' | 'workflow' | 'assets'>): AvailableInput[] {
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
