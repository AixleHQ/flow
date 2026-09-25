import { usePage } from '@inertiajs/react';

import type { SharedProps } from 'shared/ui/types';

/**
 * False for a read-only viewer of the current company. It only hides controls:
 * the server refuses a viewer's writes whatever the page shows.
 */
export function useCanWrite(): boolean {
  return usePage<SharedProps>().props.permissions?.canWrite ?? true;
}
