import { describe, expect, it } from 'vitest';

import {
  arnPartition,
  isAccountId,
  issuerHostPath,
  subjectPatterns,
  trustPolicy,
  trustPolicyJson,
} from './awsOidcTrustPolicy';

const input = {
  accountId: '123456789012',
  issuerUrl: 'https://flow.example.com/oidc/9fK2abc',
  audience: 'sts.amazonaws.com',
  verifySubject: 'verify:integration:9',
  workflowIds: [12],
  allowDrafts: false,
};

describe('awsOidcTrustPolicy', () => {
  it('names the provider by the issuer without its scheme or a trailing slash', () => {
    expect(issuerHostPath('https://flow.example.com/oidc/9fK2abc')).toBe('flow.example.com/oidc/9fK2abc');
    expect(issuerHostPath('https://flow.example.com/oidc/9fK2abc/')).toBe('flow.example.com/oidc/9fK2abc');
  });

  it('trusts the provider for the audience and the picked workflows, with the verify subject last', () => {
    expect(trustPolicy(input)).toEqual({
      Version: '2012-10-17',
      Statement: [
        {
          Effect: 'Allow',
          Principal: { Federated: 'arn:aws:iam::123456789012:oidc-provider/flow.example.com/oidc/9fK2abc' },
          Action: ['sts:AssumeRoleWithWebIdentity', 'sts:TagSession'],
          Condition: {
            StringEquals: { 'flow.example.com/oidc/9fK2abc:aud': 'sts.amazonaws.com' },
            StringLike: { 'flow.example.com/oidc/9fK2abc:sub': ['workflow:12:step:*', 'verify:integration:9'] },
          },
        },
      ],
    });
  });

  it('adds a draft pattern per workflow only when draft test runs are allowed', () => {
    expect(subjectPatterns({ ...input, workflowIds: [12, 14, 12], allowDrafts: true })).toEqual([
      'workflow:12:step:*',
      'workflow:14:step:*',
      'draft:workflow:12:step:*',
      'draft:workflow:14:step:*',
      'verify:integration:9',
    ]);
    expect(subjectPatterns({ ...input, workflowIds: [], allowDrafts: true })).toEqual(['verify:integration:9']);
  });

  it("uses the role's partition in the provider ARN", () => {
    const policy = trustPolicy({ ...input, partition: arnPartition('arn:aws-cn:iam::123456789012:role/x') });

    expect(policy.Statement[0].Principal.Federated).toBe(
      'arn:aws-cn:iam::123456789012:oidc-provider/flow.example.com/oidc/9fK2abc',
    );
  });

  it('accepts only a 12-digit account ID', () => {
    expect(isAccountId('123456789012')).toBe(true);
    expect(isAccountId('12345678901')).toBe(false);
    expect(isAccountId('12345678901a')).toBe(false);
  });

  it('renders the policy as indented JSON that parses back to the same policy', () => {
    const json = trustPolicyJson(input);

    expect(json).toContain('\n  "Statement"');
    expect(JSON.parse(json)).toEqual(trustPolicy(input));
  });
});
