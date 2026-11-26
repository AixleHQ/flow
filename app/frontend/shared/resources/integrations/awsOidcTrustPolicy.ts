// The trust policy an AWS OIDC role needs (docs/design/aws-oidc-integration.md §5.3).

export interface TrustPolicyInput {
  accountId: string;
  issuerUrl: string;
  audience: string;
  verifySubject: string;
  /** Empty trusts every workflow of the project: the issuer already names the project. */
  workflowIds: number[];
  allowDrafts: boolean;
  /** `aws` unless the role lives in another partition (`aws-cn`, `aws-us-gov`). */
  partition?: string;
}

const ACCOUNT_ID = /^\d{12}$/;

export const isAccountId = (value: string) => ACCOUNT_ID.test(value);

/** IAM names an OIDC provider, and its condition keys, by the issuer URL without its scheme. */
export const issuerHostPath = (issuerUrl: string) => issuerUrl.replace(/^https?:\/\//, '').replace(/\/+$/, '');

export const arnPartition = (arn: string) => arn.split(':')[1] || 'aws';

export function subjectPatterns({
  workflowIds,
  allowDrafts,
  verifySubject,
}: Pick<TrustPolicyInput, 'workflowIds' | 'allowDrafts' | 'verifySubject'>): string[] {
  const ids = [...new Set(workflowIds)];
  const workflows = ids.length ? ids.map((id) => `workflow:${id}:step:*`) : ['workflow:*'];
  return [...workflows, ...(allowDrafts ? workflows.map((pattern) => `draft:${pattern}`) : []), verifySubject];
}

export function trustPolicy(input: TrustPolicyInput) {
  const provider = issuerHostPath(input.issuerUrl);
  return {
    Version: '2012-10-17',
    Statement: [
      {
        Effect: 'Allow',
        Principal: { Federated: `arn:${input.partition ?? 'aws'}:iam::${input.accountId}:oidc-provider/${provider}` },
        Action: ['sts:AssumeRoleWithWebIdentity', 'sts:TagSession'],
        Condition: {
          StringEquals: { [`${provider}:aud`]: input.audience },
          StringLike: { [`${provider}:sub`]: subjectPatterns(input) },
        },
      },
    ],
  };
}

export const trustPolicyJson = (input: TrustPolicyInput) => JSON.stringify(trustPolicy(input), null, 2);
