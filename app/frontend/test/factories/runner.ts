import type Runner from '@/types/generated/Runner';
import type RunnerSummary from '@/types/generated/RunnerSummary';

import type { JsonSchema, RunnerTypeOption } from 'shared/resources/runners/runnerConfig';

// The `: Runner` return annotation is the compile-time drift contract: if Typelizer
// regenerates Runner with a changed/added required field, this factory stops compiling.
export const buildRunner = (overrides: Partial<Runner> = {}): Runner => ({
  id: 1,
  name: 'build-box',
  projectId: null,
  integrationId: null,
  maxConcurrency: 2,
  maxEnvironments: null,
  statusReason: null,
  lastSeenAt: null,
  disabledAt: null,
  revokedAt: null,
  createdAt: '2026-10-01T00:00:00Z',
  updatedAt: '2026-10-01T00:00:00Z',
  runnerType: 'manual',
  status: 'pending',
  reusePolicy: 'reuse',
  scope: 'company',
  config: {},
  capabilities: { provisionable: false, rebuildable: false },
  createdByName: 'Ada',
  ...overrides,
});

// A runner as the pickers and the "Runs on" badge receive it (RunnerSummaryResource).
export const buildRunnerSummary = (overrides: Partial<RunnerSummary> = {}): RunnerSummary => ({
  id: 1,
  name: 'build-box',
  projectId: null,
  runnerType: 'manual',
  status: 'connected',
  deleted: false,
  operatedBy: 'Acme',
  ...overrides,
});

const ABSOLUTE_PATH: JsonSchema = { type: 'string', pattern: '^/' };

// Runners::ConfigSchema.for_type('manual') as the server sends it, keys verbatim.
export const MANUAL_CONFIG_SCHEMA: JsonSchema = {
  type: 'object',
  additionalProperties: false,
  properties: {
    reconnect_grace: { type: 'integer', minimum: 60, maximum: 7200, default: 900 },
    auto_update: { type: 'boolean', default: true },
    container: {
      type: 'object',
      additionalProperties: false,
      properties: {
        image_override: { type: 'string', minLength: 1 },
        resources: {
          type: 'object',
          additionalProperties: false,
          properties: {
            cpus: { type: 'number', exclusiveMinimum: 0 },
            memory: { type: 'string', pattern: '^[0-9]+(\\.[0-9]+)?([kKmMgGtT]i?)?$' },
          },
        },
        workspace_volume: { type: 'boolean', default: true },
        cache_mounts: {
          type: 'array',
          items: {
            type: 'object',
            additionalProperties: false,
            required: ['target'],
            properties: {
              name: { type: 'string', pattern: '^[a-z0-9][a-z0-9_.-]*$' },
              host_path: ABSOLUTE_PATH,
              target: ABSOLUTE_PATH,
            },
            oneOf: [{ required: ['name'] }, { required: ['host_path'] }],
          },
          default: [],
        },
        home_mount: {
          type: ['object', 'null'],
          additionalProperties: false,
          properties: { path: ABSOLUTE_PATH, writable: { type: 'boolean', default: false } },
        },
        extra_mounts: {
          type: 'array',
          items: {
            type: 'object',
            additionalProperties: false,
            required: ['source', 'target'],
            properties: { source: ABSOLUTE_PATH, target: ABSOLUTE_PATH, writable: { type: 'boolean', default: false } },
          },
          default: [],
        },
        acknowledged_writable_mounts: { type: 'array', items: ABSOLUTE_PATH, default: [] },
        network: { enum: ['bridge', 'host'], default: 'bridge' },
        pid: { enum: ['private', 'host'], default: 'private' },
        allow_privileged_mounts: { type: 'boolean', default: false },
        docker_socket: { type: 'boolean', default: false },
      },
    },
  },
};

export const buildRunnerTypeOption = (overrides: Partial<RunnerTypeOption> = {}): RunnerTypeOption => ({
  runnerType: 'manual',
  configSchema: MANUAL_CONFIG_SCHEMA,
  capabilities: { provisionable: false, rebuildable: false },
  ...overrides,
});
