import { usePage } from '@inertiajs/react';

import type { FeatureFlagName } from '@/types/generated/featureFlags';

import type { SharedProps } from 'shared/ui/types';

/**
 * A feature flag as the server resolved it for the current company. Only flags declared
 * `client: true` exist here, and an unknown name is a type error. False when the page did not
 * send the flag. The server decides every write whatever this returns.
 */
export function useFeatureFlag(name: FeatureFlagName): boolean {
  return usePage<SharedProps>().props.features?.[name] ?? false;
}
