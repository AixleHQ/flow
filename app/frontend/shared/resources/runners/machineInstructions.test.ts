import { describe, expect, it } from 'vitest';

import {
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
        `curl -fsSLo aixle-runner ${binary.url}`,
        `echo "${'a'.repeat(64)}  aixle-runner" | sha256sum -c -`,
        'chmod 0755 aixle-runner',
        '',
        '# 2. Register this machine (this uses up the token)',
        'sudo ./aixle-runner configure --url https://flow.example.com --token arreg_abc-123_x --name build-01',
        '',
        '# 3. Run it as a service that survives logout and reboot',
        'sudo ./aixle-runner service install && sudo aixle-runner service start',
      ].join('\n'),
    );
  });

  it('adds --no-auto-update to configure on request', () => {
    expect(installScript({ registration, binary, name: 'm', noAutoUpdate: true })).toContain(
      '--name m --no-auto-update',
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
