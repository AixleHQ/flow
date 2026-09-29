import { vi } from 'vitest';

type Answer = unknown | ((init?: RequestInit) => unknown);

/** Requests that reached the default fetch() — no test answered them. setup.ts fails the test on any. */
export const unansweredFetches: string[] = [];

export const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

export async function unansweredFetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  unansweredFetches.push(`${init?.method ?? 'GET'} ${String(input)}`);
  return jsonResponse({});
}

const matcher = (route: string) => {
  const [method, path] = route.includes(' ') ? route.split(' ') : [null, route];
  const pattern = new RegExp(`^${path.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/:\w+/g, '[^/]+')}$`);
  return (requestMethod: string, requestPath: string) =>
    (method === null || method === requestMethod) && pattern.test(requestPath);
};

/**
 * Answers the listed requests — keyed "METHOD /path" (or "/path" for any method; `:id`
 * matches one segment; the query string is ignored) — with their JSON body, a Response, or a
 * function of the request init returning either. Every other request stays unanswered and
 * still fails the test.
 */
export function answerFetch(routes: Record<string, Answer>) {
  const table = Object.entries(routes).map(([route, answer]) => ({ matches: matcher(route), answer }));

  return vi.spyOn(globalThis, 'fetch').mockImplementation(async (input, init) => {
    const path = String(input).split('?')[0];
    const route = table.find(({ matches }) => matches(init?.method ?? 'GET', path));
    if (!route) return unansweredFetch(input, init);

    const { answer } = route;
    const body = typeof answer === 'function' ? (answer as (i?: RequestInit) => unknown)(init) : answer;
    return body instanceof Response ? body : jsonResponse(body);
  });
}
