const COMPANY_PATH = /^\/company\/([a-z0-9-]+)(?=\/|$)/;

/**
 * The company this tab is on, from its URL (/company/<slug>/…), or null on a
 * page that belongs to no company. Inertia pushes a visit's URL before it
 * renders the page, so a page building its links already reads its own.
 */
export function currentCompanySlug(): string | null {
  if (typeof window === 'undefined') return null;
  return COMPANY_PATH.exec(window.location.pathname)?.[1] ?? null;
}
