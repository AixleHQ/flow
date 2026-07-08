import '@testing-library/jest-dom/vitest';
import { describe, expect, it } from 'vitest';

import { renderPage, screen } from 'test/renderPage';

import { GoogleLoginButton } from './GoogleLoginButton';

describe('GoogleLoginButton', () => {
  it('renders a POST form targeting the Google auth path (OmniAuth request phase must not accept GET, see CVE-2015-9284)', () => {
    const { container } = renderPage(<GoogleLoginButton />);

    const form = container.querySelector('form');
    expect(form).toHaveAttribute('method', 'post');
    expect(form).toHaveAttribute('action', '/auth/google');

    const button = screen.getByRole('button', { name: 'Sign in with Google' });
    expect(button).toBeInTheDocument();
    expect(button).toHaveAttribute('type', 'submit');
  });

  it('renders the Google icon svg inside the button', () => {
    const { container } = renderPage(<GoogleLoginButton />);

    const svg = container.querySelector('svg');
    expect(svg).toBeInTheDocument();
    expect(svg).toHaveAttribute('viewBox', '0 0 24 24');
  });

  it('forwards extra Button props (e.g. className) onto the rendered element', () => {
    renderPage(<GoogleLoginButton className="custom-google-cta" />);

    const button = screen.getByRole('button', { name: 'Sign in with Google' });
    expect(button).toHaveClass('custom-google-cta');
  });

  it('shows the loading state when the loading prop is forwarded', () => {
    renderPage(<GoogleLoginButton loading />);

    const button = screen.getByRole('button', { name: 'Sign in with Google' });
    expect(button).toHaveAttribute('data-loading', 'true');
  });

  it('honours a disabled prop forwarded to the underlying Button', () => {
    renderPage(<GoogleLoginButton disabled />);

    const button = screen.getByRole('button', { name: 'Sign in with Google' });
    expect(button).toHaveAttribute('data-disabled', 'true');
  });
});
