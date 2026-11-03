import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderAuthedPage, screen } from 'test/renderPage';

import Privacy from './Privacy';

describe('Profile/Privacy', () => {
  it('shows the current answer', () => {
    renderAuthedPage(<Privacy analyticsConsent="granted" analyticsAvailable />, { props: {} });

    expect(screen.getByRole('switch', { name: /Product analytics/ })).toBeChecked();
    expect(screen.getByRole('tab', { name: 'Privacy' })).toHaveAttribute('aria-selected', 'true');
  });

  it('cannot be switched on where nothing is collected', () => {
    renderAuthedPage(<Privacy analyticsConsent={null} analyticsAvailable={false} />, { props: {} });

    expect(screen.getByRole('switch', { name: /Product analytics/ })).toBeDisabled();
    expect(screen.getByText('This installation does not collect product analytics.')).toBeInTheDocument();
  });
});
