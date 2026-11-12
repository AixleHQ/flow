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
