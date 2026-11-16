import { useEffect, useRef } from 'react';

import { type Guard, registerGuard, requestClose } from './guards';

interface Options {
  /** The form's values differ from the ones it opened with. */
  dirty: boolean;
  /**
   * A request that saves the form is in flight. Such a form is not dirty: its save is not leaving
   * it, and the visit or close that follows a successful save must not ask. Pass false for a form
   * with no request of its own. The hook decides; callers never fold this into `dirty`.
   */
  saving: boolean;
  /**
   * Whether the dialog or drawer holding the form is open. A closed one keeps its state while it
   * stays mounted, and must not hold up leaving the page. Omit for a form that is the page itself.
   */
  opened?: boolean;
  /** Closes the dialog or drawer holding the form. Omit for a form that is the page itself. */
  onClose?: () => void;
  /** Offers Save in the question. Resolves true once saved. Omit while the form is invalid. */
  onSave?: () => Promise<boolean>;
}

/**
 * Asks "unsaved changes?" before a dirty form is left by any way out: an Inertia visit to another
 * page, browser back/forward, a reload or tab close, and — through the returned close handler —
 * the form's own Cancel, X, Escape or overlay click. Pass that handler as the dialog's `onClose`
 * and to its Cancel button, never to a successful save, which closes on purpose.
 */
export function useUnsavedChanges({ dirty, saving, opened = true, onClose, onSave }: Options) {
  const guard = useRef<Guard>({ dirty: false });
  guard.current.dirty = dirty && !saving && opened;
  guard.current.onSave = onSave;

  useEffect(() => registerGuard(guard.current), []);

  return () => requestClose(guard.current, () => onClose?.());
}
