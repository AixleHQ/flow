import { describe, expect, it } from 'vitest';

import {
  dockerScript,
  installScript,
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

describe('dockerScript', () => {
  it('registers with configure, then runs the image with the Docker socket', () => {
    const script = dockerScript({ registration, name: 'build-01', host: 'linux' });
    const image = "'ghcr.io/aixlehq/aixle-runner:0.1.0'";
    expect(script).toContain("RUNNER_DIR='/var/lib/aixle-runner'");
    expect(script).toContain(
      `sudo docker run --rm --user 0:0 -e AIXLE_RUNNER_DIR="$RUNNER_DIR" -v "$RUNNER_DIR:$RUNNER_DIR" -v /var/run/docker.sock:/var/run/docker.sock -v aixle-runner-docker-root:/var/lib/docker:ro ${image} configure --url 'https://flow.example.com' --token 'arreg_abc-123_x' --name 'build-01'`,
    );
    expect(script).toContain('-d --name aixle-runner --restart unless-stopped');
    expect(script.match(/-v \/var\/run\/docker\.sock:\/var\/run\/docker\.sock/g)).toHaveLength(3);
    expect(script).toContain('# sudo docker run --rm --user 0:0');
    expect(script).toContain('unregister');
    expect(script).not.toContain('--no-auto-update');
  });

  it('keeps the directory under the home directory on macOS, without sudo', () => {
    const script = dockerScript({ registration, name: 'm', host: 'macos' });
    expect(script).toContain('RUNNER_DIR="$HOME/aixle-runner"');
    expect(script).not.toContain('sudo');
  });

  it('quotes the token as shell data', () => {
    expect(dockerScript({ registration: { ...registration, token: '$(id)' }, name: 'm', host: 'linux' })).toContain(
      "--token '$(id)'",
    );
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
