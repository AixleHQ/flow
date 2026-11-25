import { router } from '@inertiajs/react';
import { Text } from '@mantine/core';
import { modals } from '@mantine/modals';

import {
  companyProjectAwsOidcRolePath,
  companyProjectAwsOidcRolesPath,
  connectCompanyProjectAwsOidcPath,
  disconnectCompanyProjectAwsOidcPath,
  verifyCompanyProjectAwsOidcRolePath,
} from 'shared/routes';

import { issuerHostPath } from './awsOidcTrustPolicy';
import { requestJson } from './requestJson';

export interface AwsOidcRole {
  id: number;
  name: string;
  roleArn: string;
  region: string;
  sessionDurationSeconds: number;
  accountId: string | null;
}

export interface AwsOidcActivity {
  id: number;
  createdAt: string;
  roleName: string;
  subject: string;
  userName: string | null;
  workflowName: string | null;
  stepName: string | null;
  workflowRunId: number | null;
}

export interface AwsOidcConnection {
  id: number;
  status: 'active' | 'inactive' | 'error';
  issuerUrl: string;
  audience: string;
  verifySubject: string;
  roles: AwsOidcRole[];
  workflows: { id: number; name: string }[];
  activity: AwsOidcActivity[];
}

export interface AwsOidcProps {
  canManage?: boolean;
  connection?: AwsOidcConnection | null;
}

/** The verify endpoint renders AwsOidc::Verifier::Result as it is, so its keys stay snake_case. */
export interface AwsOidcVerifyResult {
  ok: boolean;
  assumed_role_arn: string | null;
  failure: string | null;
  message: string | null;
  subject: string;
}

export interface AwsOidcRoleInput {
  name: string;
  roleArn: string;
  region: string;
  sessionDurationSeconds: number;
}

export const connectAwsOidc = (projectId: number, onConnected?: () => void) =>
  router.post(connectCompanyProjectAwsOidcPath(projectId), {}, { preserveScroll: true, onSuccess: onConnected });

export const confirmAwsOidcDisconnect = (projectId: number) =>
  modals.openConfirmModal({
    title: 'Disconnect AWS OIDC',
    children: (
      <Text size="sm">
        AWS refuses every token from this project until you reconnect, so steps that use these roles fail. The roles
        stay here, and the trust policies stay in AWS.
      </Text>
    ),
    labels: { confirm: 'Disconnect', cancel: 'Cancel' },
    confirmProps: { color: 'red' },
    onConfirm: () => router.delete(disconnectCompanyProjectAwsOidcPath(projectId), { preserveScroll: true }),
  });

const roleCount = (count: number) => `${count} ${count === 1 ? 'role' : 'roles'}`;

export const awsOidcSummary = (connection: AwsOidcConnection) =>
  connection.status === 'active'
    ? `${issuerHostPath(connection.issuerUrl)} · ${roleCount(connection.roles.length)}`
    : `Disconnected: AWS refuses its tokens · ${roleCount(connection.roles.length)}`;

const roleBody = (role: AwsOidcRoleInput) => ({
  aws_oidc_role: {
    name: role.name.trim(),
    role_arn: role.roleArn.trim(),
    region: role.region.trim(),
    session_duration_seconds: role.sessionDurationSeconds,
  },
});

export const saveAwsOidcRole = (
  projectId: number,
  roleId: number | null,
  role: AwsOidcRoleInput,
  callbacks: { onSuccess: () => void; onError: (errors: Record<string, string>) => void; onFinish?: () => void },
) => {
  const options = { preserveScroll: true, ...callbacks };
  return roleId == null
    ? router.post(companyProjectAwsOidcRolesPath(projectId), roleBody(role), options)
    : router.patch(companyProjectAwsOidcRolePath(projectId, roleId), roleBody(role), options);
};

export const confirmAwsOidcRoleDelete = (projectId: number, role: AwsOidcRole) =>
  modals.openConfirmModal({
    title: 'Delete role',
    children: (
      <Text size="sm">
        Delete <b>{role.name}</b>? Workflows and steps that use it lose it. The role in AWS is not changed.
      </Text>
    ),
    labels: { confirm: 'Delete', cancel: 'Cancel' },
    confirmProps: { color: 'red' },
    onConfirm: () => router.delete(companyProjectAwsOidcRolePath(projectId, role.id), { preserveScroll: true }),
  });

export const verifyAwsOidcRole = (projectId: number, roleId: number) =>
  requestJson(
    verifyCompanyProjectAwsOidcRolePath(projectId, roleId),
    { method: 'POST' },
    'Flow could not verify the role',
  ) as Promise<AwsOidcVerifyResult>;
