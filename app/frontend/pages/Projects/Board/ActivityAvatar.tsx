import { Box } from '@mantine/core';
import { IconRobot } from '@tabler/icons-react';

export function ActivityAvatar({ actorType, actorName }: { actorType: string; actorName: string }) {
  const isAgent = actorType === 'agent';
  return (
    <Box
      style={{
        width: 28,
        height: 28,
        borderRadius: '50%',
        flexShrink: 0,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        fontSize: 11,
        fontWeight: 600,
        background: isAgent ? 'var(--mantine-color-brand-light)' : 'rgba(209,207,205,0.07)',
        border: `1px solid ${isAgent ? 'var(--mantine-color-brand-light-hover)' : 'var(--app-border-default)'}`,
        color: isAgent ? 'var(--app-primary)' : 'var(--mantine-color-dimmed)',
      }}
    >
      {isAgent ? (
        <IconRobot size={13} />
      ) : (
        actorName
          .split(' ')
          .map((w) => w[0])
          .join('')
          .slice(0, 2)
          .toUpperCase()
      )}
    </Box>
  );
}
