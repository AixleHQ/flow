import { useEffect, useRef } from 'react';

interface Flushable {
  flush: () => void;
}

/**
 * Sends debounced saves that are still waiting when the tab is hidden — the last
 * moment a page reliably gets before it is closed. Mantine's `flushOnUnmount`
 * covers leaving the page inside the app; this covers leaving the browser.
 */
export function useFlushWhenHidden(...pending: Flushable[]) {
  const pendingRef = useRef(pending);
  pendingRef.current = pending;

  useEffect(() => {
    const flushIfHidden = () => {
      if (document.visibilityState === 'hidden') pendingRef.current.forEach((debounced) => debounced.flush());
    };
    document.addEventListener('visibilitychange', flushIfHidden);
    return () => document.removeEventListener('visibilitychange', flushIfHidden);
  }, []);
}
