import { useCallback, useEffect, useRef, useState } from 'react';

import { notifyApiFailure, toApiError } from 'shared/lib/apiFetch';

interface SaveState {
  saving: boolean;
  /** The last save that finished was refused or never arrived. */
  failed: boolean;
  /** Resolves true when the save went through; a refusal is also shown to the user. */
  withSave: <T>(promise: Promise<T>) => Promise<boolean>;
}

export function useSavingState(): SaveState {
  const [count, setCount] = useState(0);
  const [failed, setFailed] = useState(false);
  const promiseIdsRef = useRef(new Set<number>());
  const nextIdRef = useRef(0);

  // A Response is a failure unless it is ok: fetch resolves for a 422 or a 500 too,
  // and treating that as saved is how an edit the server refused showed "Saved".
  const withSave = useCallback(async <T>(promise: Promise<T>): Promise<boolean> => {
    const id = nextIdRef.current++;
    promiseIdsRef.current.add(id);
    setCount((c) => c + 1);

    try {
      const result = await promise;
      const refused = result instanceof Response && !result.ok;
      setFailed(refused);
      if (refused) notifyApiFailure(await toApiError(result.clone()), 'The change was not saved');
      return !refused;
    } catch (error) {
      setFailed(true);
      notifyApiFailure(error, 'The change was not saved');
      return false;
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

  return { saving: count > 0, failed, withSave };
}
