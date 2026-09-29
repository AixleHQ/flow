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
