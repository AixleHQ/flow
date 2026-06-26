import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderPage, screen } from 'test/renderPage';

import { GoogleLoginButton } from './GoogleLoginButton';

describe('GoogleLoginButton', () => {
  it('renders a link labelled "Sign in with Google" pointing at the Google auth path', () => {
    renderPage(<GoogleLoginButton />);

    const link = screen.getByRole('link', { name: 'Sign in with Google' });
    expect(link).toBeInTheDocument();
    expect(link).toHaveAttribute('href', '/auth/google');
  });

  it('renders the Google icon svg inside the button', () => {
    const { container } = renderPage(<GoogleLoginButton />);

    const svg = container.querySelector('svg');
    expect(svg).toBeInTheDocument();
    expect(svg).toHaveAttribute('viewBox', '0 0 24 24');
  });

  it('forwards extra Button props (e.g. className) onto the rendered element', () => {
    renderPage(<GoogleLoginButton className="custom-google-cta" />);

    const link = screen.getByRole('link', { name: 'Sign in with Google' });
    expect(link).toHaveClass('custom-google-cta');
  });

  it('shows the loading state when the loading prop is forwarded', () => {
    renderPage(<GoogleLoginButton loading />);

    const link = screen.getByRole('link', { name: 'Sign in with Google' });
    expect(link).toHaveAttribute('data-loading', 'true');
  });

  it('honours a disabled prop forwarded to the underlying Button', () => {
    renderPage(<GoogleLoginButton disabled />);

    const link = screen.getByRole('link', { name: 'Sign in with Google' });
    expect(link).toHaveAttribute('data-disabled', 'true');
  });
});
