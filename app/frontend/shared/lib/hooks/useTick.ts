import { useEffect, useState } from 'react';

/**
 * Returns a timestamp that updates every `intervalMs` while `enabled` is true.
 * Useful for forcing re-renders so that time-dependent computations stay fresh
 * (e.g. elapsed-time counters).
 */
export function useTick(enabled: boolean, intervalMs = 1000): number {
  const [tick, setTick] = useState(() => Date.now());

  useEffect(() => {
    if (!enabled) return;

    const id = setInterval(() => setTick(Date.now()), intervalMs);
    return () => clearInterval(id);
  }, [enabled, intervalMs]);

  return tick;
}
