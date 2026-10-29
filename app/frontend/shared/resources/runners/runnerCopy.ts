import type { Runner, RunnerSummary } from '@/types/generated';

import { formatDateTime } from 'shared/lib/formatDate';

import { humanize } from './runnerConfig';

/**
 * Words for the schema's keys. The form's fields come from the schema; this only names them, so a
 * key without an entry still renders, under its humanized name.
 */
export const FIELD_COPY: Record<string, { label: string; description?: string }> = {
  container: {
    label: 'Give the agent your toolchain',
    description:
      'The agent runs in the stock agent image. Your machine’s compilers, CLIs and caches reach it only through what you mount into the container.',
  },
  'container.extra_mounts': {
    label: 'Extra mounts',
    description: 'Host directories mounted into the container, e.g. a toolchain directory. Absolute paths only.',
  },
  'container.home_mount': {
    label: 'Home directory mount',
    description: 'Mount a home directory on the machine for dotfiles and user-installed tools.',
  },
  'container.home_mount.path': { label: 'Home directory path' },
  'container.home_mount.writable': { label: 'Writable' },
  'container.cache_mounts': {
    label: 'Cache mounts',
    description: 'Package caches kept between sessions: a named volume, or a path on the machine.',
  },
  'container.acknowledged_writable_mounts': {
    label: 'Writable host mounts',
    description:
      'The agent can write to these paths on the machine, outside what Aixle creates. Scrub removes what Aixle wrote there, not what the agent wrote.',
  },
  'container.workspace_volume': {
    label: 'Keep a workspace volume',
    description: 'Repository checkouts stay on a volume between sessions.',
  },
  'container.image_override': {
    label: 'Image override',
    description: 'An image built FROM the Aixle base image. Leave empty for the stock agent image.',
  },
  'container.resources': { label: 'Resources', description: 'CPU and memory limits for the agent container.' },
  'container.resources.cpus': { label: 'CPUs' },
  'container.resources.memory': { label: 'Memory', description: 'For example 4g or 512m.' },
  'container.network': {
    label: 'Network',
    description: 'host gives the agent the machine’s network, e.g. for a VPN client.',
  },
  'container.pid': { label: 'Process namespace', description: 'host lets the agent see the machine’s processes.' },
  'container.allow_privileged_mounts': {
    label: 'Allow privileged mounts',
    description: 'Required before the Docker socket can be mounted.',
  },
  'container.docker_socket': {
    label: 'Mount the Docker socket',
    description: 'Lets the agent run Docker on the machine.',
  },
  reconnect_grace: {
    label: 'Reconnect grace (seconds)',
    description: 'How long a session waits for a runner that lost its connection.',
  },
  auto_update: { label: 'Auto-update', description: 'The runner updates itself to the recommended version.' },
};

/**
 * Mounts first: they are how a manual machine's toolchain reaches the agent (§6.8). A key that is
 * not listed renders after these, in the schema's order.
 */
export const FIELD_ORDER = [
  'container',
  'container.extra_mounts',
  'container.home_mount',
  'container.cache_mounts',
  'container.acknowledged_writable_mounts',
  'container.workspace_volume',
  'container.image_override',
  'container.resources',
  'container.network',
  'container.pid',
  'container.allow_privileged_mounts',
  'container.docker_socket',
  'reconnect_grace',
  'auto_update',
];

export const fieldLabel = (path: string): string => FIELD_COPY[path]?.label ?? humanize(path.split('.').pop() ?? path);

export const RUNNER_TYPE_COPY: Record<string, { title: string; description: string }> = {
  manual: {
    title: 'Manual',
    description: 'A machine you operate. You install aixle-runner on it, and sessions run in containers there.',
  },
  coder: { title: 'Coder', description: 'Workspaces provisioned from a Coder template.' },
  kubernetes: { title: 'Kubernetes', description: 'A pod per session in your cluster.' },
};

export const runnerTypeTitle = (type: string): string => RUNNER_TYPE_COPY[type]?.title ?? humanize(type);

/** What `reuse_policy` means on each type (§7.1). */
export const REUSE_POLICY_COPY: Partial<Record<Runner['runnerType'], Record<Runner['reusePolicy'], string>>> = {
  manual: {
    reuse:
      'The machine keeps the pulled images, the workspace volume and the cache volumes. Aixle scrubs after every session.',
    fresh:
      'Fresh on a manual runner wipes everything Aixle put on the machine after every session. It does not give you a new machine.',
  },
  coder: {
    reuse: 'The workspace is kept, with its pulled image, repository clones and cache mounts.',
    fresh: 'A new workspace is created for every session and destroyed after it.',
  },
};

/** The type's own default when the runner does not set one (Runner::DEFAULT_REUSE_POLICY). */
export const DEFAULT_REUSE_POLICY: Record<Runner['runnerType'], Runner['reusePolicy']> = {
  manual: 'reuse',
  coder: 'reuse',
  kubernetes: 'fresh',
};

export const lastSeen = (runner: Pick<Runner, 'lastSeenAt'>): string =>
  runner.lastSeenAt ? formatDateTime(runner.lastSeenAt) : 'Never';

/** Why a referenced runner cannot take a launch, in the §3.4 wording, or null when it can be tried. */
export function runnerUnusableReason(runner: RunnerSummary): string | null {
  if (runner.deleted) return `Runner "${runner.name}" is deleted.`;
  if (runner.status === 'revoked') return `Runner "${runner.name}" is revoked.`;
  if (runner.status === 'disabled') return `Runner "${runner.name}" is disabled.`;
  return null;
}
