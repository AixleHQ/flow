import type { PendingVisit } from '@inertiajs/core';
import { router } from '@inertiajs/react';

import { askUnsavedChanges, dismissUnsavedChangesQuestion } from './askUnsavedChanges';

export interface Guard {
  dirty: boolean;
  onSave?: () => Promise<boolean>;
}

const guards = new Set<Guard>();
let bypass = false;
let skipNextPopState = false;
let current: { url: string; state: unknown } | null = null;
let removeListeners: (() => void) | null = null;
let holdingBrowserHistory = false;

function dirtyGuards() {
  return [...guards].filter((guard) => guard.dirty);
}

function ask(dirty: Guard[], leave: () => void) {
  // With two dirty forms one Save would keep only half the changes, so it is offered for one form only.
  const save = dirty.length === 1 ? dirty[0].onSave : undefined;

  askUnsavedChanges({
    onDiscard: leave,
    onSave: save
      ? async () => {
          const saved = await save();
          if (saved) leave();
          return saved;
        }
      : undefined,
  });
}

function rememberCurrentEntry() {
  current = { url: window.location.href, state: window.history.state };
}

function onBeforeUnload(event: BeforeUnloadEvent) {
  if (bypass || dirtyGuards().length === 0) return;
  event.preventDefault();
  event.returnValue = '';
}

function replay(visit: PendingVisit) {
  bypass = true;
  try {
    router.visit(visit.url.href, {
      method: visit.method,
      replace: visit.replace,
      preserveScroll: visit.preserveScroll,
      preserveState: visit.preserveState,
      only: visit.only,
      except: visit.except,
      headers: visit.headers,
    });
  } finally {
    bypass = false;
  }
}

// A reload, a partial reload or a filter in the query stays on the page and keeps the form.
function leavesPage(visit: PendingVisit) {
  return visit.method === 'get' && !visit.prefetch && visit.url.pathname !== window.location.pathname;
}

function onInertiaBefore(event: CustomEvent<{ visit: PendingVisit }>) {
  const { visit } = event.detail;
  if (bypass || !leavesPage(visit)) return;
  const dirty = dirtyGuards();
  if (dirty.length === 0) return;

  event.preventDefault();
  ask(dirty, () => replay(visit));
}

// Inertia swaps the page on popstate without a cancelable `before` event, and by then the browser
// has already moved to the other entry. This listener has to run ahead of Inertia's own: both sit on
// window, where listeners run in the order they were added whatever their capture flag, so it is
// added before Inertia boots (see `holdBrowserHistory`). It holds the page, and pushes the left entry
// back on top. Whichever way the user went, the entry they were going to is then one step back, so
// leaving after all is `history.back()`.
function onPopState(event: PopStateEvent) {
  if (skipNextPopState) {
    skipNextPopState = false;
    return;
  }
  if (bypass || !current) return;
  const dirty = dirtyGuards();
  if (dirty.length === 0) return;

  event.stopImmediatePropagation();
  window.history.pushState(current.state, '', current.url);

  ask(dirty, () => {
    skipNextPopState = true;
    window.history.back();
  });
}

/**
 * Puts the browser Back/Forward hold in place. Call it once at boot, before Inertia starts: a
 * popstate listener added after Inertia's runs after it, and the page is swapped under the question.
 * It does nothing while no form is dirty. `registerGuard` calls it too, as a fallback.
 */
export function holdBrowserHistory() {
  if (holdingBrowserHistory) return;
  holdingBrowserHistory = true;
  window.addEventListener('popstate', onPopState);
}

function install() {
  bypass = false;
  skipNextPopState = false;
  rememberCurrentEntry();
  window.addEventListener('beforeunload', onBeforeUnload);
  const removeBefore = router.on('before', onInertiaBefore);
  const removeNavigate = router.on('navigate', rememberCurrentEntry);

  return () => {
    window.removeEventListener('beforeunload', onBeforeUnload);
    removeBefore();
    removeNavigate();
  };
}

export function registerGuard(guard: Guard) {
  guards.add(guard);
  holdBrowserHistory();
  removeListeners ??= install();

  return () => {
    guards.delete(guard);
    if (guards.size === 0 && removeListeners) {
      removeListeners();
      removeListeners = null;
      dismissUnsavedChangesQuestion();
    }
  };
}

/** Asks before a form's own close (Cancel, X, Escape, the overlay) when that form is dirty. */
export function requestClose(guard: Guard, close: () => void) {
  if (!guard.dirty) {
    close();
    return;
  }
  ask([guard], close);
}

/**
 * Runs a leave that is not a GET visit — signing out — after the same question a visit to another
 * page gets.
 */
export function confirmLeave(leave: () => void) {
  const go = () => {
    allowUnload();
    leave();
  };
  const dirty = dirtyGuards();
  if (dirty.length === 0) go();
  else ask(dirty, go);
}

/**
 * Lets the next page unload through without asking — call it right before a redirect the user
 * cannot stay through (an OAuth hand-off, a step-up sign-in) or a native form POST.
 */
export function allowUnload() {
  bypass = true;
  window.addEventListener('pageshow', () => (bypass = false), { once: true });
}
