export function tourSelector(key: string): string {
  return `[data-tour="${key}"]`;
}

/** The element marked `data-tour="key"`, once React has rendered it; null after `timeoutMs`. */
export function waitForTarget(key: string, timeoutMs: number): Promise<Element | null> {
  const find = () => document.querySelector(tourSelector(key));
  const found = find();
  if (found || timeoutMs <= 0) return Promise.resolve(found);

  return new Promise((resolve) => {
    const done = (element: Element | null) => {
      observer.disconnect();
      window.clearTimeout(timer);
      resolve(element);
    };
    const observer = new MutationObserver(() => {
      const element = find();
      if (element) done(element);
    });
    const timer = window.setTimeout(() => done(null), timeoutMs);
    observer.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['data-tour'] });
  });
}
