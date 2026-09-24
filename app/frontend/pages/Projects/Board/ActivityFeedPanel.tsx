import { Box, Button, Drawer, Loader, Text } from '@mantine/core';

import type BoardActivity from 'types/generated/BoardActivity';

import { ActivityAvatar } from './ActivityAvatar';
import { formatRelativeTime } from './boardFormat';
import { useBoardActivitiesLoadMore } from './useBoardActivitiesLoadMore';

// --- Activity Feed (slide-over, non-modal — AC-27) ---

export function ActivityFeedPanel({
  projectId,
  initialActivities,
  opened,
  onClose,
}: {
  projectId: number;
  initialActivities: BoardActivity[];
  opened: boolean;
  onClose: () => void;
}) {
  const { activities, loading, loadMore, hasMore } = useBoardActivitiesLoadMore(projectId, initialActivities);

  return (
    <Drawer
      opened={opened}
      onClose={onClose}
      position="right"
      size={340}
      withOverlay={false}
      lockScroll={false}
      withCloseButton
      title={
        <Text fw={600} size="sm">
          Activity
        </Text>
      }
      styles={{
        header: { borderBottom: '1px solid var(--app-border-default)', padding: '12px 16px' },
        body: { padding: '0 16px' },
      }}
    >
      {loading && activities.length === 0 ? (
        <Box ta="center" py="xl">
          <Loader size="sm" />
        </Box>
      ) : activities.length === 0 ? (
        <Text size="xs" c="dimmed" ta="center" py="xl">
          No activity yet.
        </Text>
      ) : (
        <>
          {activities.map((a) => (
            <Box
              key={a.id}
              style={{
                display: 'flex',
                gap: 10,
                padding: '12px 0',
                borderBottom: '1px solid rgba(41,39,38,0.6)',
              }}
            >
              <ActivityAvatar actorType={a.actorType} actorName={a.actorName} />
              <Box style={{ flex: 1, minWidth: 0 }}>
                <Text size="xs" style={{ lineHeight: 1.5, color: 'var(--mantine-color-text)' }}>
                  <strong>{a.actorName}</strong>{' '}
                  {a.description
                    .replace(a.actorName, '')
                    .trim()
                    .replace(/^moved '(.+?)' from/, "moved '$1' from")}
                </Text>
                <Text size="10px" c="dimmed" mt={2}>
                  {formatRelativeTime(a.createdAt)}
                </Text>
              </Box>
            </Box>
          ))}
          {hasMore && (
            <Button variant="subtle" size="xs" fullWidth mt="xs" onClick={loadMore} loading={loading}>
              Load more
            </Button>
          )}
        </>
      )}
    </Drawer>
  );
}
