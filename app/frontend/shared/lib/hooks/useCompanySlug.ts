import { usePage } from '@inertiajs/react';

import type { SharedProps } from 'shared/ui/types';

/**
 * The company the page shows, for a write from the chrome every signed-in page
 * carries (sidebar, banners, feedback). A page with no company in its path,
 * /profile among them, still shows one, and the server answers 404 to a write
 * that names no company rather than pick one for it.
 */
export function useCompanySlug(): string | undefined {
  return usePage<SharedProps>().props.currentUser?.currentCompany?.slug;
}
