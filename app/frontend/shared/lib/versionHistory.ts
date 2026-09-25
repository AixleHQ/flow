import type { EntityVersion, EntityVersionDetail } from '@/types/generated';

import { getPath, type Snapshot } from './versionDiff';
import type { VersionableType } from './versionSchemas';

export function describeVersion(version: EntityVersion): string {
  if (version.baseline) return 'Initial state';
  switch (version.event) {
    case 'created':
      return version.duplicatedFromId ? 'Created as a copy' : 'Created';
    case 'saved':
      return 'Saved';
    case 'reverted':
      return `Reverted to v${version.restoredFromNumber ?? '?'}`;
    case 'archived':
      return 'Archived';
    case 'restored':
      return 'Restored from archive';
  }
}

const REFERENCE_KEYS: [string, string][] = [
  ['agent_id', 'Agent'],
  ['tool_ids', 'Tool'],
  ['skill_ids', 'Skill'],
  ['mcp_server_ids', 'MCPServer'],
  ['repository_ids', 'Repository'],
  ['config_item_ids', 'ConfigItem'],
];

/** [model, id] for every resource a workflow snapshot names. */
function referencedIds(snapshot: Snapshot): [string, string][] {
  const ids: [string, string][] = [];
  const config = (snapshot.config ?? {}) as Record<string, unknown>;
  for (const [key, model] of REFERENCE_KEYS) {
    for (const id of [config[`base_${key}`]].flat()) if (id !== undefined && id !== null) ids.push([model, String(id)]);
  }
  for (const step of (snapshot.steps ?? []) as Record<string, unknown>[]) {
    for (const [key, model] of REFERENCE_KEYS) {
      for (const id of [step[key]].flat()) if (id !== undefined && id !== null) ids.push([model, String(id)]);
    }
  }
  return ids;
}

/** What a revert to `target` would do beyond the diff itself — said before it happens. */
export function revertWarnings(
  type: VersionableType,
  target: Snapshot,
  current: Snapshot,
  references: EntityVersionDetail['references'],
): string[] {
  const warnings: string[] = [];
  if (type === 'MCPServer') {
    const destination = (s: Snapshot) =>
      JSON.stringify(['transport', 'url', 'command', 'args'].map((k) => s[k] ?? null));
    if (destination(target) !== destination(current)) {
      warnings.push(
        'This moves the server to another address: its stored header and env values and its OAuth connections are cleared, and must be entered again.',
      );
    }
    for (const field of ['headers', 'env'] as const) {
      const wanted = Object.keys((getPath(target, `secrets.${field}`) as Record<string, unknown>) ?? {});
      const present = Object.keys((getPath(current, `secrets.${field}`) as Record<string, unknown>) ?? {});
      const missing = wanted.filter((key) => !present.includes(key));
      if (missing.length)
        warnings.push(`Secret values are never stored in history — set ${missing.join(', ')} again after reverting.`);
    }
  }
  if (type === 'Workflow') {
    const unavailable = referencedIds(target)
      .map(([model, id]) => references[model]?.[id])
      .filter((ref): ref is { name: string; archived: boolean } => Boolean(ref?.archived))
      .map((ref) => ref.name);
    if (unavailable.length) {
      warnings.push(
        `It references archived resources that runs will skip until restored: ${[...new Set(unavailable)].join(', ')}.`,
      );
    }
  }
  return warnings;
}
