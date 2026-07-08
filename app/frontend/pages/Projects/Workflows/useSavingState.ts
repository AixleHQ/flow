import { useCallback, useState } from 'react';

export function useSavingState() {
  const [count, setCount] = useState(0);
  const withSave = useCallback(async (promise: Promise<unknown>) => {
    setCount((c) => c + 1);
    try {
      await promise;
    } finally {
      setCount((c) => c - 1);
    }
  }, []);
  return { saving: count > 0, withSave };
}
