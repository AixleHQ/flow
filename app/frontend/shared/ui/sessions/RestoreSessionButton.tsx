import { ActionIcon, Tooltip } from '@mantine/core';
import { IconRestore } from '@tabler/icons-react';
import { useState } from 'react';

import { restoreDaysLeft, restoreSession } from 'shared/lib/sessionRestore';

interface Props {
  sessionId: number;
  restoreExpiresAt: string | null;
}

/** A list row's Restore action for a suspended session: starts the continuing session and opens it. */
export function RestoreSessionButton({ sessionId, restoreExpiresAt }: Props) {
  const [loading, setLoading] = useState(false);
  const days = restoreDaysLeft(restoreExpiresAt);
  const label = days === null ? 'Restore' : `Restore · ${days} ${days === 1 ? 'day' : 'days'} left`;

  return (
    <Tooltip label={label}>
      <ActionIcon
        variant="subtle"
        size="sm"
        loading={loading}
        aria-label={`Restore session #${sessionId}`}
        onClick={async (event) => {
          event.stopPropagation();
          setLoading(true);
          if (!(await restoreSession(sessionId))) setLoading(false);
        }}
      >
        <IconRestore size={15} />
      </ActionIcon>
    </Tooltip>
  );
}
