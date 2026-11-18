import { router } from '@inertiajs/react';
import { notifications } from '@mantine/notifications';

const NOTIFICATION_ID = 'inertia-network-error';

/**
 * A visit that never reached the server (offline, a laptop waking up, a dropped
 * connection) is a fact about the network, not a bug: Inertia would reject it as
 * an unhandled `HttpNetworkError`. The user is told once instead.
 */
export const registerInertiaNetworkErrorNotice = (): (() => void) =>
  router.on('networkError', (event) => {
    event.preventDefault();
    notifications.show({
      id: NOTIFICATION_ID,
      title: "Can't reach the server",
      message: 'Check your connection and try again.',
      color: 'red',
      autoClose: 6000,
    });
  });
