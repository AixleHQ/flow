import { Deferred, Head, router } from '@inertiajs/react';
import { Avatar, Badge, Box, Card, Group, Select, Skeleton, Stack, Text, Title } from '@mantine/core';
import { useCallback, useMemo } from 'react';

import { AuthLayout } from 'layouts/AuthLayout';

import { formatDateMedium } from 'shared/lib/formatDate';
import { getInitials } from 'shared/lib/getInitials';
import { RoleTag } from 'shared/resources/members/MembersContent';
import { SessionFeedTable, type SessionFeedRow } from 'shared/resources/sessions/SessionFeedTable';
import { PERIOD_OPTIONS, UsageAnalytics, type Period } from 'shared/resources/usage/UsageAnalytics';
import { UsageLimitsCard, type UsageLimitsEntry } from 'shared/resources/usage/UsageLimitsCard';
import { companyProjectSessionPath, companySessionPath, userPath } from 'shared/routes';
import type { UserRole } from 'shared/ui';
import { StatusBadge } from 'shared/ui/StatusBadge';

import classes from './Show.module.css';

interface Member {
  id: number;
  name: string;
  email: string;
  role: string;
  state: string;
  position?: string | null;
  invitedAt: string | null;
  acceptedAt: string | null;
  createdAt: string;
}

export interface UserShowProps {
  member: Member;
  viewerIsSelf: boolean;
  total: number;
  sessions: SessionFeedRow[];
  /** The company-wide session page is admin-only; admins can open any row. */
  viewerIsAdmin: boolean;
  /** Projects this viewer may open a session in (owner / collaborator). */
  accessibleProjectIds: number[];
  usageLimits?: UsageLimitsEntry[];
  /** Window the spend charts cover. The panels read their own deferred props. */
  period: Period;
}

/**
 * The organization-visible member profile.
 *
 * Read-only by construction: nothing here mutates anything, and the parts of
 * the owner's own Profile that do — connecting an agent, the MCP token, the
 * session-sharing switches, "leave company" — are deliberately absent rather
 * than disabled. The one thing this page adds over the Members row is the
 * answer to "is this person's CLI plan spent?", which is why Usage limits sits
 * above the session list instead of under it.
 */
function UserShow({
  member,
  viewerIsSelf,
  total,
  sessions,
  viewerIsAdmin,
  accessibleProjectIds,
  usageLimits,
  period,
}: UserShowProps) {
  const displayName = member.name || member.email;
  const accessible = useMemo(() => new Set(accessibleProjectIds), [accessibleProjectIds]);

  // An admin reaches every session through the company page; everybody else
  // only through a project they are on. No route at all → the row stays in the
  // list (it still reports what the work cost) but is not a link.
  const sessionHref = useCallback(
    (session: SessionFeedRow) => {
      if (viewerIsAdmin) return companySessionPath(session.id);
      if (session.projectId != null && accessible.has(session.projectId)) {
        return companyProjectSessionPath(session.projectId, session.id);
      }
      return null;
    },
    [viewerIsAdmin, accessible],
  );

  return (
    <AuthLayout>
      <Head title={displayName} />

      <Card p={24} mb="lg">
        <Group gap="md" wrap="nowrap" align="flex-start">
          <Avatar
            size={56}
            radius="xl"
            styles={{
              root: {
                background: 'var(--app-bg-elevated)',
                border: '1px solid var(--app-border-default)',
                color: 'var(--app-text-secondary)',
              },
            }}
          >
            {getInitials(displayName)}
          </Avatar>
          <Box style={{ minWidth: 0, flex: 1 }}>
            <Group gap={8} wrap="nowrap">
              <Title order={3} style={{ margin: 0 }}>
                {displayName}
              </Title>
              {viewerIsSelf && (
                <Badge size="sm" variant="default">
                  You
                </Badge>
              )}
            </Group>
            <Text size="sm" c="dimmed">
              {member.email}
            </Text>
            <Group gap={8} mt={10}>
              <RoleTag role={member.role as UserRole} />
              <StatusBadge state={member.state} size="sm" />
              {member.position && (
                <Badge size="sm" variant="default">
                  {member.position}
                </Badge>
              )}
              <Text size="xs" c="dimmed">
                Member since {formatDateMedium(member.acceptedAt ?? member.invitedAt ?? member.createdAt)}
              </Text>
            </Group>
          </Box>
        </Group>
      </Card>

      {/* Deferred, exactly as on the owner's own Profile: the numbers come from
          the runtime vendor over HTTP, and a slow provider must not hold up the
          session list below. An empty set renders nothing at all. */}
      <Box mb="lg">
        <Deferred data="usageLimits" fallback={<Skeleton height={180} radius="sm" />}>
          <UsageLimitsCard entries={usageLimits ?? []} ownerName={viewerIsSelf ? null : displayName} />
        </Deferred>
      </Box>

      {/* Aixle spend, not vendor allowance — the card above is the plan, this is
          what the work cost us. Same panels, services and deferral group as the
          owner's own Profile -> Usage. */}
      <Group justify="space-between" align="baseline" gap="xs" mb="md">
        <Title order={5} style={{ margin: 0 }}>
          Usage
        </Title>
        <Select
          value={period}
          onChange={(value) =>
            router.get(userPath(member.id), { period: value ?? '30d' }, { preserveState: true, preserveScroll: true })
          }
          data={PERIOD_OPTIONS}
          size="sm"
          w={140}
          aria-label="Usage period"
        />
      </Group>

      <UsageAnalytics period={period} />

      <Stack gap={12}>
        <Group justify="space-between" align="baseline" gap="xs">
          <Title order={5} style={{ margin: 0 }}>
            Sessions &amp; runs
          </Title>
          <span className={classes.count}>
            {total} {total === 1 ? 'entry' : 'entries'}
          </span>
        </Group>
        <SessionFeedTable
          sessions={sessions}
          showUser={false}
          sessionHref={sessionHref}
          emptyLabel={`${displayName} hasn't run anything in this company yet`}
        />
      </Stack>
    </AuthLayout>
  );
}

export default UserShow;
