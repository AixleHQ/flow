import type { McpServer } from './McpServersContent';

// Health signals a catalog-installed MCP server can carry, ordered by how much
// they should interrupt someone scanning a table.
//
// Only `drift` is an incident: a server's tool declarations moved after the
// install was approved, which is the shape of a rug-pull. The rest are standing
// facts about a working server — worth surfacing, never worth shouting about.
export type ServerHealthLevel = 'critical' | 'warning' | 'info';

export interface ServerHealthSignal {
  kind: 'drift' | 'delisted' | 'unpinned' | 'unverified' | 'update';
  level: ServerHealthLevel;
  /** Two or three words, readable without the tooltip open. */
  label: string;
  /** What happened and what it means, in the tooltip. */
  detail: string;
}

const listNames = (names: string[] | undefined): string => (names ?? []).join(', ');

const driftDetail = (server: McpServer): string => {
  const drift = server.toolDrift;
  if (!drift) return '';

  const parts: string[] = [];
  if (drift.changed?.length) parts.push(`changed: ${listNames(drift.changed)}`);
  if (drift.added?.length) parts.push(`added: ${listNames(drift.added)}`);
  if (drift.removed?.length) parts.push(`removed: ${listNames(drift.removed)}`);
  return parts.join(' · ');
};

// Highest severity first, so a row's first icon is its worst news.
export const serverHealthSignals = (server: McpServer): ServerHealthSignal[] => {
  const signals: ServerHealthSignal[] = [];

  if (server.toolDrift) {
    signals.push({
      kind: 'drift',
      level: 'critical',
      label: 'Tools changed',
      detail: `This server now declares different tools than when it was installed — ${driftDetail(server)}. Review before the next session uses it.`,
    });
  }

  if (server.connectorStatus === 'deleted') {
    signals.push({
      kind: 'delisted',
      level: 'critical',
      label: 'Removed from registry',
      detail:
        'The public registry withdrew this connector, which usually means spam, malware, or a policy violation. It keeps running until you remove it.',
    });
  } else if (server.connectorStatus === 'deprecated') {
    signals.push({
      kind: 'delisted',
      level: 'warning',
      label: 'Deprecated upstream',
      detail: 'The registry marked this connector deprecated. It still works, but it is no longer maintained.',
    });
  }

  if (server.connectorName && server.connectorVersionPinned === false) {
    signals.push({
      kind: 'unpinned',
      level: 'warning',
      label: 'Version not pinned',
      detail:
        'The registry published no fixed version for this package, so a different release can be pulled at any session start.',
    });
  }

  if (server.connectorUpdateVersion) {
    signals.push({
      kind: 'update',
      level: 'info',
      label: 'Update available',
      detail: `The catalog now carries ${server.connectorUpdateVersion}. Updating changes which code runs, so it stays your call.`,
    });
  }

  if (server.connectorName && server.transport === 'stdio' && !server.toolBaseline) {
    signals.push({
      kind: 'unverified',
      level: 'info',
      label: 'Not checked',
      detail:
        'This package runs inside your agent container, so its tools are not probed from here. Changes to what it declares will not be detected.',
    });
  }

  return signals;
};

export const hasDrift = (server: McpServer): boolean => !!server.toolDrift;

export const driftedServers = (servers: McpServer[]): McpServer[] => servers.filter(hasDrift);
