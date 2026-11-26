import { describe, expect, it } from 'vitest';

import {
  dockerCommand,
  installCommand,
  installScript,
  isValidKeepDirectory,
  isValidMachineName,
  suggestMachineName,
  type MachineBinary,
  type MachineRegistration,
} from './machineInstructions';

const binary: MachineBinary = {
  platform: 'linux-amd64',
  url: 'https://flow.example.com/runner/v1/releases/0.1.0/linux-amd64',
  sha256: 'a'.repeat(64),
};
const registration: MachineRegistration = {
  token: 'arreg_abc-123_x',
  expiresAt: '2026-11-12T10:00:00Z',
  gatewayUrl: 'https://flow.example.com',
  version: '0.1.0',
  binaries: [binary],
};

describe('installScript', () => {
  it('downloads and verifies, registers, then installs and starts the service', () => {
    expect(installScript({ registration, binary, name: 'build-01', noAutoUpdate: false })).toBe(
      [
        '# 1. Download aixle-runner 0.1.0 (linux-amd64) and verify it',
        `curl -fsSLo aixle-runner '${binary.url}'`,
        `echo '${'a'.repeat(64)}  aixle-runner' | sha256sum -c -`,
        'chmod 0755 aixle-runner',
        '',
        '# 2. Register this machine (this uses up the token)',
        "sudo ./aixle-runner configure --url 'https://flow.example.com' --token 'arreg_abc-123_x' --name 'build-01'",
        '',
        '# 3. Run it as a service that survives logout and reboot',
        'sudo ./aixle-runner service install && sudo ./aixle-runner service start',
      ].join('\n'),
    );
  });

  it('adds --no-auto-update to configure on request', () => {
    expect(installScript({ registration, binary, name: 'm', noAutoUpdate: true })).toContain(
      "--name 'm' --no-auto-update",
    );
  });

  it('quotes the URLs and the token as shell data', () => {
    const script = installScript({
      registration: { ...registration, gatewayUrl: "https://x.example/'; id; '", token: '$(id)' },
      binary: { ...binary, url: 'https://x.example/a b' },
      name: 'm',
      noAutoUpdate: false,
    });
    expect(script).toContain("--url 'https://x.example/'\\''; id; '\\'''");
    expect(script).toContain("--token '$(id)'");
    expect(script).toContain("curl -fsSLo aixle-runner 'https://x.example/a b'");
  });
});

const IMAGE = "'ghcr.io/aixlehq/aixle-runner:0.1.0'";
const SOCKET = '-v /var/run/docker.sock:/var/run/docker.sock';
const ENV =
  "-e AIXLE_RUNNER_URL='https://flow.example.com' -e AIXLE_RUNNER_TOKEN='arreg_abc-123_x' -e AIXLE_RUNNER_NAME='build-01'";
const REGISTRY = '-v "$HOME/.docker/config.json:/root/.docker/config.json:ro"';
const KEPT = '-d --restart unless-stopped';
const OFF = '-e AIXLE_RUNNER_UNREGISTER_ON_STOP=0';
const docker = (options: Partial<Parameters<typeof dockerCommand>[0]> = {}) =>
  dockerCommand({ registration, name: 'build-01', privateRegistry: false, keep: 'none', ...options });

describe('dockerCommand', () => {
  it('is the one foreground command of the design by default', () => {
    expect(docker()).toBe(`docker run --rm --name aixle-runner ${SOCKET} ${ENV} ${IMAGE}`);
  });

  it('has nothing the default does not need', () => {
    const command = docker();
    for (const absent of [
      'sudo',
      '--user',
      'RUNNER_DIR',
      'docker-root',
      'configure',
      ' -d ',
      'UNREGISTER_ON_STOP',
      'var/lib/aixle-runner',
      '\n',
    ]) {
      expect(command).not.toContain(absent);
    }
    expect(command.match(/ -v /g)).toHaveLength(1);
  });

  it('adds the Docker config for a private registry, and nothing else', () => {
    expect(docker({ privateRegistry: true })).toBe(
      `docker run --rm --name aixle-runner ${SOCKET} ${REGISTRY} ${ENV} ${IMAGE}`,
    );
  });

  it('keeps the registration in a named volume, which replaces --rm and turns unregister-on-stop off', () => {
    expect(docker({ keep: 'volume' })).toBe(
      `docker run ${KEPT} --name aixle-runner ${SOCKET} -v aixle-runner:/var/lib/aixle-runner ${ENV} ${OFF} ${IMAGE}`,
    );
  });

  it('keeps the registration in a directory at any path, quoted', () => {
    expect(docker({ keep: { directory: '/srv/runner state' } })).toBe(
      `docker run ${KEPT} --name aixle-runner ${SOCKET} -v '/srv/runner state:/var/lib/aixle-runner' ${ENV} ${OFF} ${IMAGE}`,
    );
  });

  it('combines the registry mount with each keep option', () => {
    expect(docker({ privateRegistry: true, keep: 'volume' })).toBe(
      `docker run ${KEPT} --name aixle-runner ${SOCKET} ${REGISTRY} -v aixle-runner:/var/lib/aixle-runner ${ENV} ${OFF} ${IMAGE}`,
    );
    expect(docker({ privateRegistry: true, keep: { directory: '/data/r' } })).toBe(
      `docker run ${KEPT} --name aixle-runner ${SOCKET} ${REGISTRY} -v '/data/r:/var/lib/aixle-runner' ${ENV} ${OFF} ${IMAGE}`,
    );
  });

  it('never has --user or sudo, whatever the options', () => {
    for (const keep of ['none', 'volume', { directory: '/d' }] as const) {
      for (const privateRegistry of [false, true]) {
        const command = docker({ keep, privateRegistry });
        expect(command).not.toContain('--user');
        expect(command).not.toContain('sudo');
      }
    }
  });

  it('quotes the platform values and the directory as shell data', () => {
    const command = docker({
      registration: { ...registration, token: '$(id)', gatewayUrl: "https://x.example/'; id; '" },
      name: "it's",
      keep: { directory: "/d'; id; '" },
    });
    expect(command).toContain("-e AIXLE_RUNNER_TOKEN='$(id)'");
    expect(command).toContain(String.raw`-e AIXLE_RUNNER_URL='https://x.example/'\''; id; '\'''`);
    expect(command).toContain(String.raw`-e AIXLE_RUNNER_NAME='it'\''s'`);
    expect(command).toContain(String.raw`-v '/d'\''; id; '\'':/var/lib/aixle-runner'`);
  });
});

describe('installCommand', () => {
  it('pipes the platform script into a root shell with the token and name', () => {
    expect(installCommand({ registration, name: 'build-01', noAutoUpdate: false })).toBe(
      "curl -fsSL 'https://flow.example.com/runner/v1/machine-install.sh' | sudo sh -s -- --token 'arreg_abc-123_x' --name 'build-01'",
    );
  });

  it('adds --no-auto-update on request', () => {
    expect(installCommand({ registration, name: 'm', noAutoUpdate: true })).toMatch(/--name 'm' --no-auto-update$/);
  });

  it('quotes the values as shell data', () => {
    const command = installCommand({
      registration: { ...registration, token: '$(id)', gatewayUrl: "https://x.example/'; id" },
      name: "a'b",
      noAutoUpdate: false,
    });
    expect(command).toContain("--token '$(id)'");
    expect(command).toContain(String.raw`--name 'a'\''b'`);
    expect(command).toContain(String.raw`curl -fsSL 'https://x.example/'\''; id/runner/v1/machine-install.sh'`);
  });
});

describe('isValidKeepDirectory', () => {
  it('wants an absolute path on one line, without a colon', () => {
    expect(isValidKeepDirectory('/var/lib/aixle-runner')).toBe(true);
    expect(isValidKeepDirectory('/with space')).toBe(true);
    for (const bad of ['', 'relative', '~/runner', '/a\nb', '/data:ro', '/a:b']) expect(isValidKeepDirectory(bad)).toBe(false);
  });
});

describe('machine names', () => {
  it('accepts a plain name and refuses anything a shell would read', () => {
    expect(isValidMachineName('build-01.eu_west')).toBe(true);
    for (const bad of ['', '-x', 'a b', 'a;rm -rf /', '$(id)', 'a'.repeat(64), 'naïve']) {
      expect(isValidMachineName(bad)).toBe(false);
    }
  });

  it('suggests a valid name from the runner name', () => {
    expect(suggestMachineName('GPU Box (EU)')).toBe('gpu-box-eu-01');
    expect(suggestMachineName('***')).toBe('machine-01');
    expect(isValidMachineName(suggestMachineName('x'.repeat(200)))).toBe(true);
  });
});
