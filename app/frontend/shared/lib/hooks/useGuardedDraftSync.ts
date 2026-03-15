import { useCallback, useEffect, useRef, useState } from 'react';

interface UseGuardedDraftSyncOptions<T> {
  serverValue: T | null | undefined;
  getIdentity: (value: T) => string | number;
}

interface UseGuardedDraftSyncResult<T> {
  draft: T | null;
  updateDraft: (updater: (current: T) => T) => void;
  replaceDraft: (next: T) => void;
  markSaveStarted: () => number;
  hasPendingServerValue: boolean;
  applyPendingServerValue: () => void;
  discardPendingServerValue: () => void;
}

export function useGuardedDraftSync<T>({
  serverValue,
  getIdentity,
}: UseGuardedDraftSyncOptions<T>): UseGuardedDraftSyncResult<T> {
  const [draft, setDraft] = useState<T | null>(serverValue ?? null);
  const [hasPendingServerValue, setHasPendingServerValue] = useState(false);

  const editVersionRef = useRef(0);
  const lastStartedSaveVersionRef = useRef<number | null>(null);
  const pendingServerValueRef = useRef<T | null>(null);
  const currentIdentityRef = useRef<string | number | null>(serverValue ? getIdentity(serverValue) : null);
  const getIdentityRef = useRef(getIdentity);

  useEffect(() => {
    getIdentityRef.current = getIdentity;
  }, [getIdentity]);

  const applyServerValue = useCallback((nextValue: T) => {
    setDraft(nextValue);
    editVersionRef.current = 0;
    lastStartedSaveVersionRef.current = null;
    pendingServerValueRef.current = null;
    currentIdentityRef.current = getIdentityRef.current(nextValue);
    setHasPendingServerValue(false);
  }, []);

  useEffect(() => {
    if (!serverValue) {
      setDraft(null);
      editVersionRef.current = 0;
      lastStartedSaveVersionRef.current = null;
      pendingServerValueRef.current = null;
      currentIdentityRef.current = null;
      setHasPendingServerValue(false);
      return;
    }

    const nextIdentity = getIdentityRef.current(serverValue);

    if (currentIdentityRef.current !== nextIdentity) {
      applyServerValue(serverValue);
      return;
    }

    const isPristine = editVersionRef.current === 0;
    const hasNoNewEditsSinceSaveStarted =
      lastStartedSaveVersionRef.current !== null && editVersionRef.current === lastStartedSaveVersionRef.current;

    if (isPristine || hasNoNewEditsSinceSaveStarted) {
      applyServerValue(serverValue);
      return;
    }

    pendingServerValueRef.current = serverValue;
    setHasPendingServerValue(true);
  }, [serverValue, applyServerValue]);

  const updateDraft = useCallback((updater: (current: T) => T) => {
    setDraft((current) => {
      if (current === null) return current;
      editVersionRef.current += 1;
      return updater(current);
    });
  }, []);

  const replaceDraft = useCallback((next: T) => {
    editVersionRef.current += 1;
    setDraft(next);
  }, []);

  const markSaveStarted = useCallback(() => {
    lastStartedSaveVersionRef.current = editVersionRef.current;
    return lastStartedSaveVersionRef.current;
  }, []);

  const applyPendingServerValue = useCallback(() => {
    if (!pendingServerValueRef.current) return;
    applyServerValue(pendingServerValueRef.current);
  }, [applyServerValue]);

  const discardPendingServerValue = useCallback(() => {
    pendingServerValueRef.current = null;
    setHasPendingServerValue(false);
  }, []);

  return {
    draft,
    updateDraft,
    replaceDraft,
    markSaveStarted,
    hasPendingServerValue,
    applyPendingServerValue,
    discardPendingServerValue,
  };
}
