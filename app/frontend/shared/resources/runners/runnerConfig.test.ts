import { describe, expect, it } from 'vitest';

import { MANUAL_CONFIG_SCHEMA } from 'test/factories/runner';

import {
  accessWideners,
  configForSubmit,
  errorMessages,
  placeConfigErrors,
  setAt,
  setKeys,
  writableHostMounts,
} from './runnerConfig';

describe('runnerConfig', () => {
  it('sets a nested key and drops a group that becomes empty, but not a nullable object', () => {
    const withNetwork = setAt({}, MANUAL_CONFIG_SCHEMA, ['container', 'network'], 'host');
    expect(withNetwork).toEqual({ container: { network: 'host' } });
    expect(setAt(withNetwork, MANUAL_CONFIG_SCHEMA, ['container', 'network'], undefined)).toEqual({});

    const home = setAt({}, MANUAL_CONFIG_SCHEMA, ['container', 'home_mount'], { path: '/home/ci' });
    expect(setAt(home, MANUAL_CONFIG_SCHEMA, ['container', 'home_mount', 'path'], undefined)).toEqual({
      container: { home_mount: {} },
    });
  });

  it('lists the writable host mounts as ManualAdapter does: home by path, the others by target', () => {
    const config = {
      container: {
        home_mount: { path: '/home/ci', writable: true },
        extra_mounts: [
          { source: '/opt/tools', target: '/opt/tools' },
          { source: '/srv/data', target: '/data', writable: true },
        ],
        cache_mounts: [
          { name: 'pip', target: '/root/.cache/pip' },
          { host_path: '/var/cache/npm', target: '/root/.npm' },
        ],
      },
    };

    expect(writableHostMounts(config)).toEqual(['/home/ci', '/data', '/root/.npm']);
  });

  it('sends only the acknowledgements of mounts that are still writable', () => {
    const config = {
      container: {
        extra_mounts: [{ source: '/srv', target: '/srv', writable: true }],
        acknowledged_writable_mounts: ['/srv', '/gone'],
      },
    };
    expect(configForSubmit(config, MANUAL_CONFIG_SCHEMA)).toEqual({
      container: { extra_mounts: config.container.extra_mounts, acknowledged_writable_mounts: ['/srv'] },
    });

    expect(configForSubmit({ container: { acknowledged_writable_mounts: ['/gone'] } }, MANUAL_CONFIG_SCHEMA)).toEqual(
      {},
    );
    expect(configForSubmit({ auto_update: false }, MANUAL_CONFIG_SCHEMA)).toEqual({ auto_update: false });
  });

  it('places each config message at the field its leading key names, and keeps the rest apart', () => {
    const { byField, unplaced } = placeConfigErrors(
      [
        'container.extra_mounts[0].source must be an absolute path',
        'container.home_mount.path is required on a manual runner',
        'reconnect_grace must be between 60 and 7200',
        'ephemeral is not a config key: it is set per machine at registration',
        'must be an object',
      ],
      MANUAL_CONFIG_SCHEMA,
    );

    expect(byField).toEqual({
      'container.extra_mounts': ['container.extra_mounts[0].source must be an absolute path'],
      'container.home_mount.path': ['container.home_mount.path is required on a manual runner'],
      reconnect_grace: ['reconnect_grace must be between 60 and 7200'],
    });
    expect(unplaced).toEqual([
      'ephemeral is not a config key: it is set per machine at registration',
      'must be an object',
    ]);
  });

  it('reads the server errors whether they arrive as a string or a list', () => {
    expect(errorMessages({ name: 'is taken', runnerType: ['is not available yet'] }, 'name', 'runnerType')).toEqual([
      'is taken',
      'is not available yet',
    ]);
    expect(errorMessages(undefined, 'name')).toEqual([]);
  });

  it('calls out the options that widen access, and flattens the set keys to their paths', () => {
    const config = {
      auto_update: false,
      container: {
        network: 'host',
        docker_socket: true,
        allow_privileged_mounts: true,
        extra_mounts: [{ source: '/opt', target: '/opt' }],
      },
    };

    expect(accessWideners(config)).toEqual([
      'Mounts /opt at /opt, read-only',
      'Shares the machine’s network (network: host)',
      'Allows privileged mounts',
      'Mounts the Docker socket: the agent has root on the machine',
    ]);
    expect(setKeys(config, MANUAL_CONFIG_SCHEMA).map(([key]) => key)).toEqual([
      'auto_update',
      'container.network',
      'container.docker_socket',
      'container.allow_privileged_mounts',
      'container.extra_mounts',
    ]);
  });
});
