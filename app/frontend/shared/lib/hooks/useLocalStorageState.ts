import { useEffect, useRef, useState } from 'react';

interface UseLocalStorageStateOptions<T> {
  skipRestore?: boolean;
  onRestore?: (value: T) => void;
}

export function useLocalStorageState<T>(
  storageKey: string | null | undefined,
  defaultValue: T,
  options?: UseLocalStorageStateOptions<T>,
): [T, React.Dispatch<React.SetStateAction<T>>] {
  const [value, setValue] = useState<T>(defaultValue);
  const [restored, setRestored] = useState(false);
  const skipRestoreRef = useRef(options?.skipRestore);
  skipRestoreRef.current = options?.skipRestore;
  const onRestoreRef = useRef(options?.onRestore);
  onRestoreRef.current = options?.onRestore;

  useEffect(() => {
    if (!storageKey || restored) return;
    if (!skipRestoreRef.current) {
      try {
        const stored = localStorage.getItem(storageKey);
        if (stored) {
          const parsed = JSON.parse(stored) as T;
          setValue(parsed);
          onRestoreRef.current?.(parsed);
        }
      } catch {
        /* ignore corrupt data */
      }
    }
    setRestored(true);
  }, [storageKey, restored]);

  useEffect(() => {
    if (!storageKey || !restored) return;
    localStorage.setItem(storageKey, JSON.stringify(value));
  }, [storageKey, value, restored]);

  return [value, setValue];
}
