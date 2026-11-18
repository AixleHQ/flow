import type { TourChapter } from './steps';

/** The tour in progress. Kept in sessionStorage: the tour crosses full page loads (Install is a plain link). */
export interface TourState {
  chapter: TourChapter;
  stepId: string;
}

/** What the person answered to the first-visit offer. */
export interface TourOfferState {
  notNowCount: number;
  dismissed: boolean;
  completed: boolean;
}

const STATE_KEY = 'aixle:product-tour';
const OFFERED_KEY = 'aixle:product-tour-offered';
const offerKey = (userId: number) => `aixle:product-tour-offer:${userId}`;
const START_EVENT = 'aixle:product-tour-start';

// Storage can throw (private mode, blocked site data); the tour then simply does not resume.
function read<T>(storage: () => Storage, key: string): T | null {
  try {
    const raw = storage().getItem(key);
    return raw ? (JSON.parse(raw) as T) : null;
  } catch {
    return null;
  }
}

function write(storage: () => Storage, key: string, value: unknown) {
  try {
    if (value === null) storage().removeItem(key);
    else storage().setItem(key, JSON.stringify(value));
  } catch {
    // see read()
  }
}

const session = () => window.sessionStorage;
const local = () => window.localStorage;

export const readTourState = () => read<TourState>(session, STATE_KEY);
export const writeTourState = (state: TourState | null) => write(session, STATE_KEY, state);

const EMPTY_OFFER: TourOfferState = { notNowCount: 0, dismissed: false, completed: false };

export const readOffer = (userId: number): TourOfferState => ({
  ...EMPTY_OFFER,
  ...read<TourOfferState>(local, offerKey(userId)),
});

export const updateOffer = (userId: number, patch: Partial<TourOfferState>) =>
  write(local, offerKey(userId), { ...readOffer(userId), ...patch });

/** Scenario A0: offered until accepted, finished, refused for good, or put off twice. */
export const shouldOffer = (offer: TourOfferState) => !offer.dismissed && !offer.completed && offer.notNowCount < 2;

/** "Not now" brings the offer back on a later visit, not on the next page of this one. */
export const offeredThisVisit = () => read<boolean>(session, OFFERED_KEY) === true;
export const markOfferedThisVisit = () => write(session, OFFERED_KEY, true);

/** Starts the tour from anywhere, such as the user menu. ProductTour picks the chapter. */
export function requestTourStart() {
  window.dispatchEvent(new CustomEvent(START_EVENT));
}

export function onTourStartRequest(listener: () => void) {
  window.addEventListener(START_EVENT, listener);
  return () => window.removeEventListener(START_EVENT, listener);
}
