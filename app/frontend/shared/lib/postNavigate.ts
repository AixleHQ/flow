import { getCsrfToken } from './apiFetch';

/**
 * A top-level navigation sent as a form POST. For endpoints that change state and
 * then redirect the browser to another site — an OAuth connect registers a client
 * and hands over to the provider's consent page — which neither a link (GET) nor
 * an Inertia visit (XHR, cannot follow a cross-origin redirect) can do.
 */
export function postNavigate(url: string, params: Record<string, string> = {}): void {
  const form = document.createElement('form');
  form.method = 'post';
  form.action = url;
  form.hidden = true;

  Object.entries({ authenticity_token: getCsrfToken(), ...params }).forEach(([name, value]) => {
    const input = document.createElement('input');
    input.type = 'hidden';
    input.name = name;
    input.value = value;
    form.appendChild(input);
  });

  document.body.appendChild(form);
  form.submit();
}
