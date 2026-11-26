import type { TourVariant } from './tours';

export interface StoredTour {
  variant: TourVariant;
  stepId: string;
  projectId: number | null;
  runId: number | null;
  /**
   * The step a click on a `click` step leads to, taken once the page it opened arrives. Stored, because
   * some of those clicks are full page loads (the template page's Install link).
   */
  pendingStepId?: string | null;
}

/** The first run the tour started, watched until it ends so the member hears about it. */
export interface WatchedRun {
  projectId: number;
  runId: number;
  since: number;
}

interface Stored {
  tour: StoredTour | null;
  watched: WatchedRun | null;
}

const STORAGE_KEY = 'product-tour';

// sessionStorage, so a reload resumes the tour and every tab runs its own.
export function readStoredTour(): Stored {
  try {
    const raw = sessionStorage.getItem(STORAGE_KEY);
    const parsed = raw ? (JSON.parse(raw) as Partial<Stored>) : {};
    return { tour: parsed.tour ?? null, watched: parsed.watched ?? null };
  } catch {
    return { tour: null, watched: null };
  }
}

export function writeStoredTour(stored: Stored): void {
  try {
    if (stored.tour || stored.watched) {
      sessionStorage.setItem(STORAGE_KEY, JSON.stringify(stored));
    } else {
      sessionStorage.removeItem(STORAGE_KEY);
    }
  } catch {
    // sessionStorage unavailable (private browsing, quota exceeded): the tour still runs in this page
  }
}
