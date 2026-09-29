import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { buildSharedProps, renderPage, screen } from 'test/renderPage';

import { PublicLayout } from './PublicLayout';

const render = (settings: Record<string, unknown> = {}) => {
  const shared = buildSharedProps();
  return renderPage(
    <PublicLayout>
      <p>A public page</p>
    </PublicLayout>,
    { props: { ...shared, currentUser: null, settings: { ...shared.settings, ...settings } } },
  );
};

describe('PublicLayout', () => {
  // /how-it-works sells a workspace a stranger can create and a price we
  // invoice. Neither exists outside the hosted product, so the link must not be
  // drawn there — it would point at a redirect.
  it('offers the marketing page where people may sign themselves up', () => {
    render({ selfServeSignup: true });

    expect(screen.getByRole('link', { name: 'How it works' })).toHaveAttribute('href', '/how-it-works');
    expect(screen.getByRole('link', { name: 'Aixle Flow' })).toHaveAttribute('href', '/how-it-works');
  });

  it('hides it everywhere else, and sends the logo to the catalog instead', () => {
    render({ selfServeSignup: false });

    expect(screen.queryByRole('link', { name: 'How it works' })).not.toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Aixle Flow' })).toHaveAttribute('href', '/templates');
  });

  // An older pod does not send the flag at all; nothing should be offered on a
  // guess.
  it('treats a missing flag as no signup', () => {
    render({});

    expect(screen.queryByRole('link', { name: 'How it works' })).not.toBeInTheDocument();
  });

  it('sends someone already signed in back into the app', () => {
    const shared = buildSharedProps();
    renderPage(
      <PublicLayout>
        <p>A public page</p>
      </PublicLayout>,
      { props: shared },
    );

    expect(screen.getByRole('link', { name: 'Open Flow' })).toHaveAttribute('href', '/');
    expect(screen.queryByRole('link', { name: 'Sign in' })).not.toBeInTheDocument();
  });
});
