import { describe, expect, it } from 'vitest';

import { gateLink } from './gates';
import type { Gate } from './types';

const gate = (overrides: Partial<Gate>): Gate =>
  ({
    id: 1,
    gateType: 'github_checks_completed',
    status: 'pending',
    ciStatus: 'pending',
    conclusion: null,
    metadata: {},
    source: {},
    ageSeconds: 0,
    expiresAt: null,
    expired: false,
    diagnosticReason: null,
    createdAt: '2026-10-16T09:00:00Z',
    resolvedAt: null,
    ...overrides,
  }) as Gate;

describe('gateLink', () => {
  it('links a Bitbucket gate to its pull request', () => {
    expect(
      gateLink(
        gate({ gateType: 'bitbucket_pr_statuses_completed', metadata: { repoFullName: 'acme/api', pullRequestId: 7 } }),
      ),
    ).toEqual({ href: 'https://bitbucket.org/acme/api/pull-requests/7', label: 'acme/api #7', kind: 'pr' });
  });

  it('has no link for a Bitbucket gate without the pull request it waits on', () => {
    expect(
      gateLink(gate({ gateType: 'bitbucket_pr_statuses_completed', metadata: { repoFullName: 'acme/api' } })),
    ).toBeNull();
  });

  it('still links a GitHub checks gate to its pull request', () => {
    expect(gateLink(gate({ metadata: { repoFullName: 'acme/api', prNumber: 3 } }))?.href).toBe(
      'https://github.com/acme/api/pull/3',
    );
  });
});
