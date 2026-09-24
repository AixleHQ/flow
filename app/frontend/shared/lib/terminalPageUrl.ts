interface TerminalUrls {
  terminalUrl?: string | null;
  websocketUrl?: string | null;
}

/**
 * The page a terminal iframe loads. The server sends it as `terminalUrl`; a pod still on
 * the release before that field sends only `websocketUrl`, so during a rolling deploy it
 * is derived from that. Delete the fallback once every pod serves `terminalUrl`.
 */
export function terminalPageUrl({ terminalUrl, websocketUrl }: TerminalUrls): string | null {
  if (terminalUrl) return terminalUrl;
  if (!websocketUrl) return null;

  try {
    const url = new URL(websocketUrl);
    url.protocol = url.protocol === 'wss:' ? 'https:' : 'http:';
    url.pathname = url.pathname.replace(/\/ws$/, '');
    return url.toString();
  } catch {
    return null;
  }
}
