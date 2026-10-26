import { usePage } from '@inertiajs/react';

import type { Features } from '@/types/generated';

import type { SharedProps } from 'shared/ui/types';

/**
 * A feature flag as the server resolved it for the current company. Only flags declared
 * `client: true` exist here: `Features` is generated from FeaturesResource, and an unknown name is a
 * type error. False when the page did not send the flag (a page served by an older pod may not know
 * it yet). The server decides every write whatever this returns.
 */
export function useFeatureFlag(name: keyof Features): boolean {
  return usePage<SharedProps>().props.features?.[name] ?? false;
}
