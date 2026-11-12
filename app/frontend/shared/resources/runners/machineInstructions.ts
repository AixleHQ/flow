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

/** The Docker choice next to the binaries' platforms in "Add machine" (DESIGN.md §6.3). */
export const DOCKER_PLATFORM = 'docker';

/** The machine a Docker runner is set up on; it decides where the runner's directory lives. */
export type DockerHost = 'linux' | 'macos';

/** The published, multi-arch runner image of a version (DESIGN.md §14.2). */
export const runnerImage = (version: string): string => `ghcr.io/aixlehq/aixle-runner:${version}`;

interface DockerScriptOptions {
  registration: MachineRegistration;
  name: string;
  host: DockerHost;
}

/**
 * The Docker variant of the sequence (DESIGN.md §6.3, §14.4): register with `configure`, then run the
 * image with the Docker socket. The runner's directory is the same path on the machine and in the
 * container, because the Docker daemon resolves the proxy sidecar's bind mounts on the machine. The
 * image does not update itself, so `configure` registers it with self-update off.
 */
export function dockerScript({ registration, name, host }: DockerScriptOptions): string {
  const image = shellQuote(runnerImage(registration.version));
  const linux = host === 'linux';
  const dir = linux ? "RUNNER_DIR='/var/lib/aixle-runner'" : 'RUNNER_DIR="$HOME/aixle-runner"';
  const sudo = linux ? 'sudo ' : '';
  // `configure` runs the Docker preflight (the daemon and the disk check, §14.4), so it needs the same
  // socket and volume as the running container.
  const common = [
    '--user 0:0',
    '-e AIXLE_RUNNER_DIR="$RUNNER_DIR"',
    '-v "$RUNNER_DIR:$RUNNER_DIR"',
    '-v /var/run/docker.sock:/var/run/docker.sock',
    '-v aixle-runner-docker-root:/var/lib/docker:ro',
  ];
  const withRoot = (...rest: string[]) => ['docker run', ...rest, ...common].join(' ');

  const configure = [
    `${sudo}${withRoot('--rm')} ${image} configure`,
    `--url ${shellQuote(registration.gatewayUrl)}`,
    `--token ${shellQuote(registration.token)}`,
    `--name ${shellQuote(name)}`,
  ].join(' ');

  return [
    '# 1. The runner keeps its binary and credentials in a directory of this machine',
    dir,
    '',
    '# 2. Register this machine (this uses up the token)',
    configure,
    '',
    '# 3. Run it; it restarts with Docker. The Docker socket lets it start the sessions',
    '#    (images from a private registry: add -v "$HOME/.docker/config.json:/root/.docker/config.json:ro")',
    `${sudo}${withRoot('-d', '--name aixle-runner', '--restart unless-stopped')} ${image}`,
    '',
    '# To remove this machine later: stop it, unregister it, delete what it left',
    '# docker stop aixle-runner && docker rm aixle-runner',
    `# ${sudo}${withRoot('--rm')} ${image} unregister`,
    `# ${sudo}rm -rf "$RUNNER_DIR" && docker volume rm aixle-runner-docker-root`,
  ].join('\n');
}
