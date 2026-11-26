import type { AwsOidcRolePicker } from '@/types/generated';

import type {
  AwsOidcActivity,
  AwsOidcConnection,
  AwsOidcProps,
  AwsOidcRole,
  AwsOidcVerifyResult,
} from 'shared/resources/integrations/awsOidcActions';

export const buildAwsOidcRole = (overrides: Partial<AwsOidcRole> = {}): AwsOidcRole => ({
  id: 1,
  name: 'prod-diagnose',
  roleArn: 'arn:aws:iam::123456789012:role/flow-diagnose',
  region: 'eu-west-1',
  sessionDurationSeconds: 3600,
  accountId: '123456789012',
  ...overrides,
});

export const buildAwsOidcActivity = (overrides: Partial<AwsOidcActivity> = {}): AwsOidcActivity => ({
  id: 1,
  createdAt: '2026-11-25T10:00:00Z',
  roleName: 'prod-diagnose',
  subject: 'workflow:12:step:34',
  userName: 'Ada',
  workflowName: 'Prod diagnosis',
  stepName: 'Diagnose',
  workflowRunId: 501,
  ...overrides,
});

export const buildAwsOidcConnection = (overrides: Partial<AwsOidcConnection> = {}): AwsOidcConnection => ({
  id: 9,
  status: 'active',
  issuerUrl: 'https://flow.example.com/oidc/9fK2abc',
  audience: 'sts.amazonaws.com',
  verifySubject: 'verify:integration:9',
  roles: [buildAwsOidcRole()],
  workflows: [
    { id: 12, name: 'Prod diagnosis' },
    { id: 14, name: 'Nightly report' },
  ],
  activity: [],
  ...overrides,
});

export const buildAwsOidcProps = (overrides: Partial<AwsOidcProps> = {}): AwsOidcProps => ({
  canManage: true,
  connection: buildAwsOidcConnection(),
  ...overrides,
});

export const buildAwsOidcVerifyResult = (overrides: Partial<AwsOidcVerifyResult> = {}): AwsOidcVerifyResult => ({
  ok: true,
  assumed_role_arn: 'arn:aws:sts::123456789012:assumed-role/flow-diagnose/flow-verify-1',
  failure: null,
  message: null,
  subject: 'verify:integration:9',
  ...overrides,
});

export const buildAwsOidcRolePicker = (overrides: Partial<AwsOidcRolePicker> = {}): AwsOidcRolePicker => ({
  id: 1,
  name: 'prod-diagnose',
  roleArn: 'arn:aws:iam::123456789012:role/flow-diagnose',
  accountId: '123456789012',
  region: 'eu-west-1',
  ...overrides,
});
