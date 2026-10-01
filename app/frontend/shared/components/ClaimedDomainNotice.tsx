import { Stack, Text } from '@mantine/core';

/** A domain that already has a workspace the person is not in (Auth::ClaimedDomain). */
export interface ClaimedDomain {
  domain: string;
  /** Absent until the workspace has proved the domain. */
  workspaceName: string | null;
  /** The sign-ins it accepts that add someone at the domain to it. */
  joinMethods: string[];
  approvalRequired: boolean;
}

const oneOf = (items: string[]) => new Intl.ListFormat('en', { type: 'disjunction' }).format(items);

export const ClaimedDomainNotice = ({ claim }: { claim: ClaimedDomain }) => {
  const { domain, workspaceName, joinMethods, approvalRequired } = claim;
  const workspace = workspaceName ? <b>{workspaceName}</b> : 'that workspace';

  return (
    <Stack gap="xs">
      <Text size="sm" c="var(--app-text-secondary)">
        {workspaceName ? (
          <>
            <b>{domain}</b> belongs to the <b>{workspaceName}</b> workspace.
          </>
        ) : (
          <>
            A workspace already uses <b>{domain}</b>.
          </>
        )}
      </Text>
      {joinMethods.length > 0 && (
        <Text size="sm" c="var(--app-text-secondary)">
          Sign in with <b>{oneOf(joinMethods)}</b>{' '}
          {approvalRequired ? (
            <>to ask to join {workspace}; one of its administrators approves the request.</>
          ) : (
            <>and you join {workspace} straight away.</>
          )}
        </Text>
      )}
      <Text size="sm" c="var(--app-text-secondary)">
        {joinMethods.length > 0 ? 'Or ask' : 'Ask'} an administrator of {workspace} to invite you.
      </Text>
    </Stack>
  );
};
