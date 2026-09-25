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

/** The query parameter the server's ContainerTicket puts on container URLs. */
const CONTAINER_TICKET_PARAM = 'aixle_ticket';

/** A container URL without its pass, so two serializations of one route compare equal. */
export function stripContainerTicket(url: string): string {
  try {
    const parsed = new URL(url);
    if (!parsed.searchParams.has(CONTAINER_TICKET_PARAM)) return url;
    parsed.searchParams.delete(CONTAINER_TICKET_PARAM);
    return parsed.toString();
  } catch {
    return url;
  }
}
