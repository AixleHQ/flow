import type { Runner } from '@/types/generated';

/**
 * The subset of JSON Schema that Runners::ConfigSchema produces. Its property names are
 * §2.7 config keys and arrive verbatim (snake_case), as the form writes them back.
 */
export interface JsonSchema {
  type?: string | string[];
  enum?: (string | number | boolean)[];
  const?: unknown;
  default?: unknown;
  properties?: Record<string, JsonSchema>;
  additionalProperties?: boolean | JsonSchema;
  required?: string[];
  items?: JsonSchema;
  oneOf?: JsonSchema[];
  minimum?: number;
  maximum?: number;
  exclusiveMinimum?: number;
  minLength?: number;
  maxLength?: number;
  pattern?: string;
  format?: string;
}

export interface RunnerTypeOption {
  runnerType: Runner['runnerType'];
  configSchema: JsonSchema;
  capabilities: Runner['capabilities'];
}

export type RunnerConfig = Record<string, unknown>;

/** Where the runners pages send their writes, one set per scope (company settings or a project). */
export interface RunnerPaths {
  list: string;
  runner: (id: number) => string;
  disable: (id: number) => string;
  enable: (id: number) => string;
  revoke: (id: number) => string;
}

export const schemaTypes = (schema: JsonSchema): string[] =>
  Array.isArray(schema.type) ? schema.type : schema.type ? [schema.type] : [];

const isPlainObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

export const pathKey = (path: string[]): string => path.join('.');

export function getAt(config: RunnerConfig, path: string[]): unknown {
  let node: unknown = config;
  for (const part of path) {
    if (!isPlainObject(node) || !(part in node)) return undefined;
    node = node[part];
  }
  return node;
}

/** The schema of the property at `path`, walking `properties` only. */
export function schemaAt(schema: JsonSchema, path: string[]): JsonSchema | undefined {
  let node: JsonSchema | undefined = schema;
  for (const part of path) {
    node = node?.properties?.[part];
    if (!node) return undefined;
  }
  return node;
}

/**
 * Sets (or, with `undefined`, removes) the key at `path` and returns a new config. A group that
 * only holds other keys (`container`) is removed once it is empty, so an untouched group is never
 * sent; a nullable object such as `home_mount` is a value of its own and stays as it is.
 */
export function setAt(config: RunnerConfig, schema: JsonSchema, path: string[], value: unknown): RunnerConfig {
  const [head, ...rest] = path;
  const next: RunnerConfig = { ...config };

  if (rest.length === 0) {
    if (value === undefined) delete next[head];
    else next[head] = value;
    return next;
  }

  const childSchema = schema.properties?.[head] ?? {};
  const child = isPlainObject(next[head]) ? (next[head] as RunnerConfig) : {};
  const updated = setAt(child, childSchema, rest, value);
  const isGroup = schemaTypes(childSchema).length === 1 && schemaTypes(childSchema)[0] === 'object';

  if (isGroup && Object.keys(updated).length === 0) delete next[head];
  else next[head] = updated;
  return next;
}

export const ACKNOWLEDGED_MOUNTS_PATH = ['container', 'acknowledged_writable_mounts'];
export const PRIVILEGED_MOUNTS_PATH = ['container', 'allow_privileged_mounts'];
export const DOCKER_SOCKET_PATH = ['container', 'docker_socket'];

const asList = (value: unknown): Record<string, unknown>[] =>
  Array.isArray(value) ? value.filter(isPlainObject) : [];

/**
 * The host paths the agent could write to outside Aixle's labels (§7.2), as
 * ManualAdapter#validate_config lists them: a writable `home_mount` by its `path` (it has no target
 * of its own), every writable `extra_mounts` entry and every host-path `cache_mounts` entry by
 * their `target`.
 */
export function writableHostMounts(config: RunnerConfig): string[] {
  const container = isPlainObject(config.container) ? config.container : {};
  const home = isPlainObject(container.home_mount) ? container.home_mount : null;
  const paths: string[] = [];

  if (home?.writable === true && typeof home.path === 'string' && home.path) paths.push(home.path);
  asList(container.extra_mounts).forEach((mount) => {
    if (mount.writable === true && typeof mount.target === 'string' && mount.target) paths.push(mount.target);
  });
  asList(container.cache_mounts).forEach((mount) => {
    if (typeof mount.host_path === 'string' && mount.host_path && typeof mount.target === 'string' && mount.target) {
      paths.push(mount.target);
    }
  });
  return [...new Set(paths)];
}

export const acknowledgedMounts = (config: RunnerConfig): string[] => {
  const value = getAt(config, ACKNOWLEDGED_MOUNTS_PATH);
  return Array.isArray(value) ? value.filter((v): v is string => typeof v === 'string') : [];
};

/**
 * The config as it is sent: what the user set, with the acknowledgements narrowed to the writable
 * mounts the config still has, so one left behind by a removed mount is not sent. Nothing else is
 * added: defaults stay in the schema (§2.7).
 */
export function configForSubmit(config: RunnerConfig, schema: JsonSchema): RunnerConfig {
  if (!schemaAt(schema, ACKNOWLEDGED_MOUNTS_PATH) || getAt(config, ACKNOWLEDGED_MOUNTS_PATH) === undefined) {
    return config;
  }
  const writable = writableHostMounts(config);
  const kept = acknowledgedMounts(config).filter((path) => writable.includes(path));
  return setAt(config, schema, ACKNOWLEDGED_MOUNTS_PATH, kept.length > 0 ? kept : undefined);
}

/**
 * The container options that widen what the agent can touch on the machine (§6.8), as the runner
 * page calls them out. Only what the config sets: every default is the isolated choice.
 */
export function accessWideners(config: RunnerConfig): string[] {
  const container = isPlainObject(config.container) ? config.container : {};
  const home = isPlainObject(container.home_mount) ? container.home_mount : null;
  const access = (writable: unknown) => (writable === true ? 'writable' : 'read-only');
  const items: string[] = [];

  asList(container.extra_mounts).forEach((mount) =>
    items.push(`Mounts ${String(mount.source ?? '?')} at ${String(mount.target ?? '?')}, ${access(mount.writable)}`),
  );
  asList(container.cache_mounts).forEach((mount) => {
    if (mount.host_path) items.push(`Mounts ${String(mount.host_path)} at ${String(mount.target ?? '?')}, writable`);
  });
  if (home) items.push(`Mounts the home directory ${String(home.path ?? '?')}, ${access(home.writable)}`);
  if (container.network === 'host') items.push('Shares the machine’s network (network: host)');
  if (container.pid === 'host') items.push('Shares the machine’s processes (pid: host)');
  if (container.allow_privileged_mounts === true) items.push('Allows privileged mounts');
  if (container.docker_socket === true) items.push('Mounts the Docker socket: the agent has root on the machine');
  return items;
}

/** The keys a config sets, flattened to their §2.7 paths (`container.network`), lists and nullable objects whole. */
export function setKeys(config: RunnerConfig, schema: JsonSchema, prefix: string[] = []): [string, unknown][] {
  return Object.entries(config).flatMap(([name, value]) => {
    const path = [...prefix, name];
    const child = schemaAt(schema, path);
    const isGroup = !!child && schemaTypes(child).length === 1 && schemaTypes(child)[0] === 'object' && !!child.properties;
    return isGroup && isPlainObject(value)
      ? setKeys(value, schema, path)
      : ([[pathKey(path), value]] as [string, unknown][]);
  });
}

/** Every property path the form renders a field for, nested objects included, array items not. */
export function fieldPaths(schema: JsonSchema, prefix: string[] = []): string[] {
  return Object.entries(schema.properties ?? {}).flatMap(([name, child]) => {
    const path = [...prefix, name];
    return [pathKey(path), ...(child.properties ? fieldPaths(child, path) : [])];
  });
}

// A config message names its key first: `container.extra_mounts[0].source must be an absolute path`.
const LEADING_PATH = /^([a-z_][a-z0-9_]*(?:\[\d+\])?(?:\.[a-z_][a-z0-9_]*(?:\[\d+\])?)*)\s/;

/**
 * Places each of the server's `config` messages at the deepest field its leading key names
 * (an array entry's message goes to the array). A message that names no rendered field is
 * returned under `unplaced`, for the form to show above its fields.
 */
export function placeConfigErrors(
  messages: string[],
  schema: JsonSchema,
): { byField: Record<string, string[]>; unplaced: string[] } {
  const known = new Set(fieldPaths(schema));
  const byField: Record<string, string[]> = {};
  const unplaced: string[] = [];

  messages.forEach((message) => {
    const match = LEADING_PATH.exec(message);
    const parts = match ? match[1].replace(/\[\d+\]/g, '').split('.') : [];
    let field: string | undefined;
    for (let length = parts.length; length > 0 && !field; length -= 1) {
      const candidate = parts.slice(0, length).join('.');
      if (known.has(candidate)) field = candidate;
    }
    if (field) (byField[field] ??= []).push(message);
    else unplaced.push(message);
  });

  return { byField, unplaced };
}

/** Inertia hands the server's errors over as a string or a list of strings per attribute. */
export function errorMessages(errors: Record<string, unknown> | undefined, ...keys: string[]): string[] {
  if (!errors) return [];
  return keys.flatMap((key) => {
    const value = errors[key];
    if (typeof value === 'string') return [value];
    if (Array.isArray(value)) return value.map(String);
    return [];
  });
}

export const humanize = (key: string): string => {
  const words = key.replace(/_/g, ' ').trim();
  return words.charAt(0).toUpperCase() + words.slice(1);
};
