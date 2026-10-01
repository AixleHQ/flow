import { Text } from '@mantine/core';
import { modals } from '@mantine/modals';
import { useRef } from 'react';

/**
 * Close handler for a dialog holding a form. With nothing unsaved it closes straight away; with
 * unsaved input it asks first, so a click on the overlay, Escape or the X does not throw the
 * input away. Pass it as the dialog's `onClose` and to its Cancel button — never to a successful
 * save, which closes on purpose.
 */
export function useConfirmClose(dirty: boolean, onClose: () => void) {
  const asking = useRef(false);

  return () => {
    if (!dirty) {
      onClose();
      return;
    }
    if (asking.current) return;

    asking.current = true;
    modals.openConfirmModal({
      title: 'Discard unsaved changes?',
      children: <Text size="sm">What you entered in this form will be lost.</Text>,
      labels: { confirm: 'Discard', cancel: 'Keep editing' },
      confirmProps: { color: 'red' },
      onConfirm: onClose,
      // Mantine listens for Escape on window, once per open modal, so the Escape that dismisses
      // this question also reaches the dialog underneath and calls back in here. Released only
      // after that event has finished, or it would re-open the question it just answered.
      onClose: () => {
        setTimeout(() => {
          asking.current = false;
        });
      },
    });
  };
}
