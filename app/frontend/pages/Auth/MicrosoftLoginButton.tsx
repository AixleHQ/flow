import { Button, type ButtonProps } from '@mantine/core';
import type { ReactNode } from 'react';

import { MICROSOFT_BRAND } from 'shared/theme/vendorColors';

import classes from './LoginPage.module.css';

const MICROSOFT_AUTH_PATH = '/auth/microsoft';

// Microsoft's four-square mark, in its published brand colours.
const MicrosoftIcon = () => (
  <svg width="20" height="20" viewBox="0 0 23 23" style={{ marginRight: 8 }}>
    <path fill={MICROSOFT_BRAND.orange} d="M1 1h10v10H1z" />
    <path fill={MICROSOFT_BRAND.green} d="M12 1h10v10H12z" />
    <path fill={MICROSOFT_BRAND.blue} d="M1 12h10v10H1z" />
    <path fill={MICROSOFT_BRAND.yellow} d="M12 12h10v10H12z" />
  </svg>
);

function getCsrfToken(): string {
  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? '';
}

// POST + CSRF token, never a plain GET link — same reasoning as the Google
// button: a GET /auth/microsoft can be triggered on a victim's session from an
// external page (CVE-2015-9284, see config/initializers/omniauth.rb).
export const MicrosoftLoginButton = ({
  children = 'Sign in with Microsoft',
  ...props
}: Omit<ButtonProps, 'component'> & { children?: ReactNode }) => (
  <form method="post" action={MICROSOFT_AUTH_PATH}>
    <input type="hidden" name="authenticity_token" value={getCsrfToken()} />
    <Button
      type="submit"
      variant="default"
      fullWidth
      size="lg"
      leftSection={<MicrosoftIcon />}
      classNames={{ root: classes.googleButton }}
      {...props}
    >
      {children}
    </Button>
  </form>
);
