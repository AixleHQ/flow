import { useCallback, useEffect, useRef, useState } from 'react';

interface SaveState {
  saving: boolean;
  withSave: <T>(promise: Promise<T>) => Promise<void>;
}

export function useSavingState(): SaveState {
  const [count, setCount] = useState(0);
  const promiseIdsRef = useRef(new Set<number>());
  const nextIdRef = useRef(0);

  const withSave = useCallback(async <T>(promise: Promise<T>): Promise<void> => {
    const id = nextIdRef.current++;
    promiseIdsRef.current.add(id);
    setCount((c) => c + 1);

    try {
      await promise;
    } catch (error) {
      // Error is handled by caller; we just ensure counter decrements
      console.error('Save operation failed:', error);
    } finally {
      promiseIdsRef.current.delete(id);
      setCount((c) => c - 1);
    }
  }, []);

  // Cleanup on unmount: ensure counter is reset if component unmounts during save
  useEffect(() => {
    const promiseIds = promiseIdsRef.current;
    return () => {
      if (promiseIds.size > 0) {
        setCount(0);
        promiseIds.clear();
      }
    };
  }, []);

  return { saving: count > 0, withSave };
}
