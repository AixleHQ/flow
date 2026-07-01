import { usePage } from '@inertiajs/react';

import type { ProjectPermissions } from 'shared/ui';

/**
 * Reads the `projectPermissions` shared Inertia prop for the current project page.
 *
 * Defaults to permissive (`true`) when the prop is absent so that non-project
 * pages and existing employee/admin behavior are unaffected. Read-only "viewer"
 * users receive `canExecute: false`, which the UI uses to hide run/mutate controls.
 */
export function useProjectPermissions(): ProjectPermissions {
  const { projectPermissions } = usePage().props as unknown as {
    projectPermissions?: ProjectPermissions;
  };
  return {
    canExecute: projectPermissions?.canExecute ?? true,
    canManage: projectPermissions?.canManage ?? true,
  };
}
