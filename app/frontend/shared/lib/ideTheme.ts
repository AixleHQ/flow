export type IdeScheme = 'light' | 'dark';

/** The IDE's preload URL, opening VS Code in `scheme`. */
export function ideUrlWithScheme(ideUrl: string, scheme: IdeScheme): string {
  const url = new URL(ideUrl);
  url.searchParams.set('scheme', scheme);
  return url.toString();
}

/**
 * The page that switches an open IDE to `scheme` in place (docker/base/watcher),
 * next to the preload page on the same origin; null if the URL is not a preload.
 */
export function ideThemeUrl(ideUrl: string, scheme: IdeScheme): string | null {
  const url = new URL(ideUrl);
  if (!url.pathname.endsWith('/fs/preload')) return null;
  url.pathname = url.pathname.replace(/\/fs\/preload$/, '/fs/theme');
  url.searchParams.delete('to');
  url.searchParams.set('scheme', scheme);
  return url.toString();
}
