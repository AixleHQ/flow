export function tourSelector(key: string): string {
  return `[data-tour="${key}"]`;
}

/** The first element matching `selector`, once React has rendered it; null after `timeoutMs` or on abort. */
export function waitForSelector(selector: string, timeoutMs: number, signal?: AbortSignal): Promise<Element | null> {
  const find = () => document.querySelector(selector);
  const found = find();
  if (found || timeoutMs <= 0 || signal?.aborted) return Promise.resolve(found);

  return new Promise((resolve) => {
    const done = (element: Element | null) => {
      observer.disconnect();
      window.clearTimeout(timer);
      signal?.removeEventListener('abort', abort);
      resolve(element);
    };
    const abort = () => done(null);
    const observer = new MutationObserver(() => {
      const element = find();
      if (element) done(element);
    });
    const timer = window.setTimeout(() => done(null), timeoutMs);
    signal?.addEventListener('abort', abort);
    observer.observe(document.body, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['data-tour'],
    });
  });
}

/** The element marked `data-tour="key"`, once React has rendered it; null after `timeoutMs`. */
export function waitForTarget(key: string, timeoutMs: number, signal?: AbortSignal): Promise<Element | null> {
  return waitForSelector(tourSelector(key), timeoutMs, signal);
}
