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
    description:
      'An image built FROM the Aixle base image. Leave empty for the stock agent image. {agent} is replaced with the session agent’s image name, e.g. claude-code, so one value serves every agent. For example ghcr.io/aixlehq/flow-{agent}:develop.',
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

/** What `reuse_policy` means on each type (§7.1), and the values the type offers. */
export const REUSE_POLICY_COPY: Partial<Record<Runner['runnerType'], Partial<Record<Runner['reusePolicy'], string>>>> =
  {
    manual: {
      reuse:
        'A scrub after every session. Repository checkouts, package caches and pulled images stay on the machine. The session container, its home and credentials, and /workspace/outputs are removed.',
      reset:
        'A reset after every session. The workspace and cache volumes are wiped, so every session clones its repositories again. Pulled images stay, and so does the machine.',
    },
    coder: {
      reuse: 'The workspace is kept, with its pulled image, repository clones and cache mounts.',
      reset: 'The workspace and cache volumes are wiped after every session. Container mode only.',
      fresh: 'A new workspace is created for every session and destroyed after it.',
    },
  };

/** The values the runner form offers for a type; `kubernetes` has one. */
export const REUSE_POLICIES: Record<Runner['runnerType'], Runner['reusePolicy'][]> = {
  manual: ['reuse', 'reset'],
  coder: ['reuse', 'reset', 'fresh'],
  kubernetes: ['fresh'],
};

/**
 * What a company runner's scrub keeps, and who sees it (§9.4). Shown on a `manual` runner's form and page:
 * with `reuse` the next session on a machine may belong to another project of the company.
 */
export const SCRUB_NOTES: string[] = [
  'A scrub removes the session container (the agent home, credential files, MCP config, prompt, context files, /tmp, the proxy CA and logs, every process) and empties /workspace/outputs. It keeps repository checkouts, package caches and pulled images.',
  'On a company runner with reuse, the next session on a machine may belong to another project, and it sees what a scrub kept: the repository checkouts and caches. Use reset, or a project runner, to keep projects apart.',
  'On a project runner, what is kept stays within that project.',
  'A reset wipes the workspace and cache volumes after every session. A session that fails is followed by a reset whatever the policy, and a machine whose reset fails, or that fails three sessions in a row, is taken out of rotation until you press Return to service.',
  'A writable host mount (home mount, an extra mount with :rw, a host-path cache mount) is outside every policy: a scrub removes what Aixle wrote there, not what the agent wrote.',
];

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
