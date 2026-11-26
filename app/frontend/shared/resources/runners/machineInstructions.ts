import type { RunnerRegistration } from '@/types/generated';

/** What "Add machine" returns once (RunnerRegistrationResource). */
export type MachineRegistration = RunnerRegistration;
export type MachineBinary = RunnerRegistration['binaries'][number];

/** A machine name goes into a shell command, so it is held to a plain, safe alphabet. */
export const MACHINE_NAME_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$/;

export const isValidMachineName = (name: string): boolean => MACHINE_NAME_PATTERN.test(name);

/** A suggestion for the machine's name from the runner's: lower case, runs of other characters as one dash. */
export function suggestMachineName(runnerName: string): string {
  const slug = runnerName
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 56);
  return `${slug || 'machine'}-01`;
}

interface ScriptOptions {
  registration: MachineRegistration;
  binary: MachineBinary;
  name: string;
  /** Adds `--no-auto-update` to `configure` (DESIGN.md §14.4). */
  noAutoUpdate: boolean;
}

/** Quotes a value as one shell word, so data from the platform is never read as shell syntax. */
export const shellQuote = (value: string): string => `'${value.replace(/'/g, `'\\''`)}'`;

/** The copy-paste sequence of DESIGN.md §6.3: download and verify, register, run as a service. */
export function installScript({ registration, binary, name, noAutoUpdate }: ScriptOptions): string {
  const configure = [
    'sudo ./aixle-runner configure',
    `--url ${shellQuote(registration.gatewayUrl)}`,
    `--token ${shellQuote(registration.token)}`,
    `--name ${shellQuote(name)}`,
    ...(noAutoUpdate ? ['--no-auto-update'] : []),
  ].join(' ');

  return [
    `# 1. Download aixle-runner ${registration.version} (${binary.platform}) and verify it`,
    `curl -fsSLo aixle-runner ${shellQuote(binary.url)}`,
    `echo ${shellQuote(`${binary.sha256}  aixle-runner`)} | sha256sum -c -`,
    'chmod 0755 aixle-runner',
    '',
    '# 2. Register this machine (this uses up the token)',
    configure,
    '',
    '# 3. Run it as a service that survives logout and reboot',
    'sudo ./aixle-runner service install && sudo ./aixle-runner service start',
  ].join('\n');
}

/** Where the image keeps the runner's registration and files (the image's `VOLUME`, add-machine.md §3.1). */
export const RUNNER_STATE_DIR = '/var/lib/aixle-runner';

/** The published, multi-arch runner image of a version (DESIGN.md §14.2). */
export const runnerImage = (version: string): string => `ghcr.io/aixlehq/aixle-runner:${version}`;

/** The name of the volume the "keep in a volume" box asks for, and of the container. */
export const DOCKER_NAME = 'aixle-runner';

/** What a Docker runner keeps across `docker stop` (add-machine.md §2.2): nothing, a named volume, or a directory. */
export type DockerKeep = 'none' | 'volume' | { directory: string };

/** A kept directory is any absolute path on the machine; it is quoted, so only its shape is checked. */
export const isValidKeepDirectory = (path: string): boolean => path.startsWith('/') && !/[\n\r\0:]/.test(path);

interface DockerCommandOptions {
  registration: MachineRegistration;
  name: string;
  /** Mounts the Docker config file, for agent images in a private registry. */
  privateRegistry: boolean;
  keep: DockerKeep;
}

/**
 * The one `docker run` of the Docker tab (add-machine.md §2.1, §2.2). The container registers itself on its
 * first start from the three variables, and the image unregisters it on stop, so by default nothing is kept
 * and the command is a single foreground `--rm` run. Each "keep" choice adds exactly its own flags and
 * turns unregister-on-stop off. Every platform value goes through `shellQuote`.
 */
export function dockerCommand({ registration, name, privateRegistry, keep }: DockerCommandOptions): string {
  const kept = keep !== 'none';
  const state =
    keep === 'volume'
      ? [`-v ${DOCKER_NAME}:${RUNNER_STATE_DIR}`]
      : typeof keep === 'object'
        ? [`-v ${shellQuote(`${keep.directory}:${RUNNER_STATE_DIR}`)}`]
        : [];

  return [
    'docker run',
    kept ? '-d --restart unless-stopped' : '--rm',
    `--name ${DOCKER_NAME}`,
    '-v /var/run/docker.sock:/var/run/docker.sock',
    ...(privateRegistry ? ['-v "$HOME/.docker/config.json:/root/.docker/config.json:ro"'] : []),
    ...state,
    `-e AIXLE_RUNNER_URL=${shellQuote(registration.gatewayUrl)}`,
    `-e AIXLE_RUNNER_TOKEN=${shellQuote(registration.token)}`,
    `-e AIXLE_RUNNER_NAME=${shellQuote(name)}`,
    ...(kept ? ['-e AIXLE_RUNNER_UNREGISTER_ON_STOP=0'] : []),
    shellQuote(runnerImage(registration.version)),
  ].join(' ');
}

interface InstallCommandOptions {
  registration: MachineRegistration;
  name: string;
  /** Adds `--no-auto-update` (DESIGN.md §14.4). */
  noAutoUpdate: boolean;
}

/** The one line of the Linux service tab: the platform's install script (add-machine.md §3.4), run as root. */
export function installCommand({ registration, name, noAutoUpdate }: InstallCommandOptions): string {
  return [
    `curl -fsSL ${shellQuote(`${registration.gatewayUrl}/runner/v1/machine-install.sh`)}`,
    '| sudo sh -s --',
    `--token ${shellQuote(registration.token)}`,
    `--name ${shellQuote(name)}`,
    ...(noAutoUpdate ? ['--no-auto-update'] : []),
  ].join(' ');
}
