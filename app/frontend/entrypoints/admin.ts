// The admin's light/dark switch. The scheme is applied before first paint by
// the inline script in app/views/administrate/application/_stylesheet.html.erb;
// this only flips it, under the key the app keeps the choice in, so the two
// stay on the same scheme.
//
// Administrate navigates with Turbo, which swaps the body without running this
// module again, so the switch is wired on every turbo:load as well as now.
const KEY = 'mantine-color-scheme-value';
const root = document.documentElement;

const scheme = () => (root.getAttribute('data-mantine-color-scheme') === 'dark' ? 'dark' : 'light');

function label(button: HTMLButtonElement) {
  const dark = scheme() === 'dark';
  button.textContent = dark ? '☀ Light theme' : '☾ Dark theme';
  button.setAttribute('aria-label', dark ? 'Switch to the light theme' : 'Switch to the dark theme');
}

function wire() {
  document.querySelectorAll<HTMLButtonElement>('[data-color-scheme-toggle]:not([data-wired])').forEach((button) => {
    button.dataset.wired = 'true';
    label(button);
    button.hidden = false;
    button.addEventListener('click', () => {
      const next = scheme() === 'dark' ? 'light' : 'dark';
      root.setAttribute('data-mantine-color-scheme', next);
      try {
        localStorage.setItem(KEY, next);
      } catch {
        // Storage refused (private mode): the switch still holds for this page.
      }
      label(button);
    });
  });
}

document.addEventListener('turbo:load', wire);
wire();
