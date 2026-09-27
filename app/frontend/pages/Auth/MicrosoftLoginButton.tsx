import type { ButtonProps } from '@mantine/core';
import type { ReactNode } from 'react';

import { AuthMethodButton } from 'shared/components/AuthMethodButton';
import { MICROSOFT_BRAND } from 'shared/theme/vendorColors';

const MICROSOFT_AUTH_PATH = '/auth/microsoft';

// Microsoft's four-square mark, in its published brand colours.
const MicrosoftIcon = () => (
  <svg width="18" height="18" viewBox="0 0 23 23" aria-hidden="true">
    <path fill={MICROSOFT_BRAND.orange} d="M1 1h10v10H1z" />
    <path fill={MICROSOFT_BRAND.green} d="M12 1h10v10H12z" />
    <path fill={MICROSOFT_BRAND.blue} d="M1 12h10v10H1z" />
    <path fill={MICROSOFT_BRAND.yellow} d="M12 12h10v10H12z" />
  </svg>
);

export const MicrosoftLoginButton = ({
  children = 'Microsoft',
  ...props
}: Omit<ButtonProps, 'component' | 'leftSection'> & { children?: ReactNode }) => (
  <AuthMethodButton icon={<MicrosoftIcon />} action={MICROSOFT_AUTH_PATH} {...props}>
    {children}
  </AuthMethodButton>
);
