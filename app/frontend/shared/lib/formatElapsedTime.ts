/** `now` defaults to the clock; a live caller passes the tick of `useElapsedTimer` so it re-derives each second. */
export function formatElapsedTime(since: string, now: number = Date.now()): string {
  const totalSeconds = Math.floor((now - new Date(since).getTime()) / 1000);
  if (totalSeconds < 60) return `${totalSeconds}s`;
  const totalMinutes = Math.floor(totalSeconds / 60);
  if (totalMinutes < 60) return `${totalMinutes}m ${totalSeconds % 60}s`;
  return `${Math.floor(totalMinutes / 60)}h ${totalMinutes % 60}m`;
}
