import { router } from '@inertiajs/react';
import { useEffect } from 'react';

export const UNSAVED_CHANGES_PROMPT = 'You have unsaved changes. Leave without saving?';

/**
 * While `dirty`, asks before the page is left: a browser unload (tab close,
 * reload, typed URL) gets the browser's own prompt, an Inertia navigation a
 * confirm. Only GET visits are guarded — a form's own save is a non-GET visit
 * and must go through.
 */
export function useUnsavedChangesGuard(dirty: boolean) {
  useEffect(() => {
    if (!dirty) return;

    const onBeforeUnload = (event: BeforeUnloadEvent) => {
      event.preventDefault();
    };
    window.addEventListener('beforeunload', onBeforeUnload);
    const removeInertiaGuard = router.on('before', (event) => {
      if (event.detail.visit.method !== 'get') return;
      if (!window.confirm(UNSAVED_CHANGES_PROMPT)) event.preventDefault();
    });

    return () => {
      window.removeEventListener('beforeunload', onBeforeUnload);
      removeInertiaGuard();
    };
  }, [dirty]);
}
