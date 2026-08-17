import { useEffect, useState } from 'react';

/** Ticks every second while `active`, so a live duration keeps counting up. */
export function useElapsedTimer(active: boolean): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (!active) return;
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, [active]);
  return now;
}
