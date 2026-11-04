// Path segments and query parameters that carry credentials or name a person:
// a sign-in, reset, invitation or share-link token is the whole secret, an OAuth
// callback carries the authorization code, and the signup confirmation link
// carries the address it was sent to. They are replaced before anything leaves
// the browser, for Sentry and for product analytics alike.
const TOKEN_PATH = /\/(invitations|share|login\/magic|password\/reset)\/[^/?#]+/g;
const SECRET_QUERY_PARAMS = ['code', 'state', 'token', 'tkn', 'session_key', 'ticket', 'email'];

export interface ScrubOptions {
  /** What a token path segment becomes. */
  placeholder?: string;
  /** Remove secret query parameters rather than mask their values. */
  dropSecrets?: boolean;
}

export const scrubQuery = (query: string, { dropSecrets = false }: ScrubOptions = {}): string => {
  const params = new URLSearchParams(query);
  SECRET_QUERY_PARAMS.forEach((name) => {
    if (!params.has(name)) return;
    if (dropSecrets) params.delete(name);
    else params.set(name, '[filtered]');
  });
  return params.toString();
};

export const scrubUrl = (url: string, options: ScrubOptions = {}): string => {
  const placeholder = options.placeholder ?? '[token]';
  const [beforeHash] = url.split('#');
  const [path, query] = beforeHash.split('?');
  const cleanPath = path.replace(TOKEN_PATH, (_match, kind: string) => `/${kind}/${placeholder}`);
  const cleanQuery = query ? scrubQuery(query, options) : '';
  return cleanQuery ? `${cleanPath}?${cleanQuery}` : cleanPath;
};

/** Whether a path is one whose URL is itself a credential: analytics never loads there. */
export const isTokenPath = (pathname: string): boolean => new RegExp(TOKEN_PATH.source).test(pathname);
