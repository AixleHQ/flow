import { describe, expect, it } from 'vitest';

import { driftedServers, serverHealthSignals } from './serverHealth';
import type { McpServer } from './types';

const server = (overrides: Partial<McpServer> = {}): McpServer => ({
  id: 1,
  name: 'Linear',
  url: 'https://mcp.linear.app/mcp',
  transport: 'http',
  headers: null,
  description: null,
  kind: 'custom',
  scopeType: 'Project',
  scopeId: 9,
  scopeIndicator: 'project',
  enabled: true,
  internal: false,
  command: null,
  env: null,
  connectorName: 'app.linear/linear',
  connectorStatus: 'active',
  connectorVersion: '1.0.0',
  connectorVersionPinned: true,
  connectorUpdateVersion: null,
  toolBaseline: true,
  toolDrift: null,
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  ...overrides,
});

describe('serverHealthSignals', () => {
  it('says nothing about a healthy connector install', () => {
    expect(serverHealthSignals(server())).toEqual([]);
  });

  it('says nothing about a hand-authored server', () => {
    const manual = server({
      connectorName: null,
      connectorStatus: null,
      connectorVersion: '1.0.0',
      connectorVersionPinned: true,
      connectorUpdateVersion: null,
      toolBaseline: false,
    });

    expect(serverHealthSignals(manual)).toEqual([]);
  });

  it('flags tools that changed after approval as critical', () => {
    const signals = serverHealthSignals(server({ toolDrift: { changed: ['search'] } }));

    expect(signals[0].kind).toBe('drift');
    expect(signals[0].level).toBe('critical');
    expect(signals[0].detail).toContain('search');
  });

  it('names added and removed tools in the drift detail', () => {
    const [signal] = serverHealthSignals(server({ toolDrift: { added: ['run_shell'], removed: ['create'] } }));

    expect(signal.detail).toContain('run_shell');
    expect(signal.detail).toContain('create');
  });

  it('treats a connector withdrawn from the registry as critical', () => {
    const [signal] = serverHealthSignals(server({ connectorStatus: 'deleted' }));

    expect(signal.kind).toBe('delisted');
    expect(signal.level).toBe('critical');
  });

  it('treats a deprecated connector as a warning, not an incident', () => {
    const [signal] = serverHealthSignals(server({ connectorStatus: 'deprecated' }));

    expect(signal.level).toBe('warning');
  });

  it('warns when the registry published no fixed version', () => {
    const [signal] = serverHealthSignals(server({ connectorVersionPinned: false }));

    expect(signal.kind).toBe('unpinned');
    expect(signal.level).toBe('warning');
  });

  it('explains that a stdio connector is not probed, rather than implying it passed', () => {
    const [signal] = serverHealthSignals(server({ transport: 'stdio', toolBaseline: false }));

    expect(signal.kind).toBe('unverified');
    expect(signal.level).toBe('info');
    expect(signal.detail).toContain('agent container');
  });

  it('does not claim a remote server is unchecked just because it lacks a baseline', () => {
    const signals = serverHealthSignals(server({ toolBaseline: false }));

    expect(signals.map((s) => s.kind)).not.toContain('unverified');
  });

  it('offers an update when the catalog moved ahead, without shouting about it', () => {
    const [signal] = serverHealthSignals(server({ connectorUpdateVersion: '2.1.0' }));

    expect(signal.kind).toBe('update');
    expect(signal.level).toBe('info');
    expect(signal.detail).toContain('2.1.0');
  });

  it('orders the worst news first', () => {
    const signals = serverHealthSignals(
      server({ toolDrift: { changed: ['search'] }, connectorStatus: 'deleted', connectorVersionPinned: false }),
    );

    expect(signals.map((s) => s.kind)).toEqual(['drift', 'delisted', 'unpinned']);
  });
});

describe('driftedServers', () => {
  it('selects only servers whose tools changed', () => {
    const clean = server({ id: 1 });
    const dirty = server({ id: 2, toolDrift: { changed: ['search'] } });

    expect(driftedServers([clean, dirty])).toEqual([dirty]);
  });
});
