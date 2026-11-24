import { router } from '@inertiajs/react';
import { Text } from '@mantine/core';
import { modals } from '@mantine/modals';

import { companyProjectInsightsPath } from 'shared/routes';

export interface InsightsProps {
  enabled: boolean;
  connection?: { status: string; organizationName: string | null; connectedAt: string } | null;
  project?: { export: boolean; insightsProjectId: string | null };
  canConnect?: boolean;
  canManage?: boolean;
  delivery?: {
    pending: number;
    oldestPendingAt: string | null;
    failed: number;
    lastError: string | null;
  };
}

export const insightsPath = (projectId: number) => companyProjectInsightsPath(projectId);

export const confirmInsightsDisconnect = (projectId: number, organizationName: string | null | undefined) =>
  modals.openConfirmModal({
    title: 'Disconnect Aixle Insights',
    children: (
      <Text size="sm">
        Every project of the company stops sending telemetry to {organizationName ?? 'Insights'}. What was already sent
        stays there.
      </Text>
    ),
    labels: { confirm: 'Disconnect', cancel: 'Cancel' },
    confirmProps: { color: 'red' },
    onConfirm: () => router.delete(`${insightsPath(projectId)}/disconnect`, { preserveScroll: true }),
  });

export const rotateInsightsSecret = (projectId: number) =>
  router.post(`${insightsPath(projectId)}/rotate`, {}, { preserveScroll: true });

// What the row says about this project, next to the company's connection.
export const insightsProjectSummary = (insights: InsightsProps) => {
  if (!insights.project?.export) return 'This project: not sent';
  const pending = insights.delivery?.pending ?? 0;
  return pending > 0 ? `This project: sent · ${pending} waiting` : 'This project: sent';
};
