// JSON rather than an Inertia visit: the dialogs keep their state between steps.
export const requestJson = async (url: string, init: RequestInit = {}, fallback = 'The request was rejected') => {
  const token = document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? '';
  const response = await fetch(url, {
    ...init,
    headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': token, Accept: 'application/json' },
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload.message || fallback);
  return payload;
};
