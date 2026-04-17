import { Dispatch, SetStateAction, useEffect, useRef, useState } from 'react';

/**
 * Persists state in localStorage with JSON serialization.
 *
 * Accepts optional `serialize` / `deserialize` callbacks for types that are
 * not directly JSON-representable (e.g. Set, Map). The callbacks are read from
 * refs so callers can pass inline functions without triggering extra effects.
 *
 * @param key - localStorage key, or null to disable persistence
 * @param defaultValue - value to use when no stored entry exists
 * @param serialize - optional custom serializer (defaults to JSON.stringify)
 * @param deserialize - optional custom deserializer (defaults to JSON.parse)
 */
export function useLocalStorage<T>(
  key: string | null,
  defaultValue: T,
  serialize: (value: T) => string = JSON.stringify,
  deserialize: (raw: string) => T = (s) => JSON.parse(s) as T,
): [T, Dispatch<SetStateAction<T>>] {
  const serializeRef = useRef(serialize);
  const deserializeRef = useRef(deserialize);
  serializeRef.current = serialize;
  deserializeRef.current = deserialize;

  const [value, setValue] = useState<T>(() => {
    if (!key) return defaultValue;
    try {
      const stored = localStorage.getItem(key);
      if (stored !== null) return deserializeRef.current(stored);
    } catch {
      // ignore read / parse errors
    }
    return defaultValue;
  });

  useEffect(() => {
    if (!key) return;
    try {
      localStorage.setItem(key, serializeRef.current(value));
    } catch {
      // ignore write errors (e.g. private-mode quota)
    }
  }, [key, value]);

  return [value, setValue];
}

/**
 * Persists a `Set<T>` in localStorage, handling all JSON serialization internally.
 *
 * @param key - localStorage key, or null to disable persistence
 * @param defaultValue - value to use when no stored entry exists (defaults to an empty Set)
 */
export function useLocalStorageSet<T>(
  key: string | null,
  defaultValue: Set<T> = new Set(),
): [Set<T>, Dispatch<SetStateAction<Set<T>>>] {
  return useLocalStorage<Set<T>>(
    key,
    defaultValue,
    (set) => JSON.stringify([...set]),
    (raw) => {
      const parsed = JSON.parse(raw) as unknown;
      return Array.isArray(parsed) ? new Set(parsed as T[]) : new Set();
    },
  );
}
