import type { Step } from '@/types/generated';

// What DataFlow::Check reports about the draft (docs/design/at-references.md §6).
export type IssueFix =
  | { kind: 'add_dependency'; stepKey: string }
  | { kind: 'attach_asset'; assetId: number }
  | { kind: 'attach_mcp_server'; mcpServerId: number };

export interface WorkflowIssue {
  severity: 'error' | 'warning';
  code: string;
  /** The payload key of the session the issue is about. */
  stepKey: string;
  field: 'instructions' | 'inputAssetSpecs' | 'outputAssetSpecs' | 'dependsOnStepIds';
  message: string;
  token?: string;
  fix?: IssueFix;
}

type GraphStep = Pick<Step, 'id' | 'dependsOnStepIds'>;

/** Every session `stepId` runs after, directly or through others — the ones whose outputs it receives. */
export function upstreamIds(steps: GraphStep[], stepId: number): Set<number> {
  const byId = new Map(steps.map((s) => [s.id, s]));
  const seen = new Set<number>();
  const stack = [...(byId.get(stepId)?.dependsOnStepIds ?? [])];
  while (stack.length > 0) {
    const id = stack.pop() as number;
    if (seen.has(id) || id === stepId) continue;
    seen.add(id);
    stack.push(...(byId.get(id)?.dependsOnStepIds ?? []));
  }
  return seen;
}

/** Every session that runs after `stepId`, directly or not. */
export function downstreamIds(steps: GraphStep[], stepId: number): Set<number> {
  return new Set(steps.filter((s) => s.id !== stepId && upstreamIds(steps, s.id).has(stepId)).map((s) => s.id));
}

/** A spec name an agent can be pointed at: one file, not a glob or a pattern. */
export const isPlainSpecName = (name: string) => name.trim() !== '' && !/[*?[]/.test(name);

const CONTAINER_PREFIXES = /^\/?workspace\/(?:outputs|assets)\//;

/**
 * Spec names are compared with the path under /workspace/outputs (or an asset's name), so the
 * container prefix authors copy from the instructions would never match — drop it, as the server does.
 */
export const normalizeSpecName = (name: string) => name.trim().replace(CONTAINER_PREFIXES, '');

/** A session's name, or its number in the sorted tree when it has none. */
export function sessionLabel(steps: Pick<Step, 'id' | 'name'>[], id: number): string {
  const step = steps.find((s) => s.id === id);
  return step?.name || `Session ${steps.findIndex((s) => s.id === id) + 1}`;
}
