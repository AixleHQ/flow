import { Button, type ButtonProps } from '@mantine/core';
import type { ReactNode } from 'react';

import { getCsrfToken } from 'shared/lib/apiFetch';

import classes from './AuthMethodButton.module.css';

type Props = Omit<ButtonProps, 'component' | 'leftSection'> & {
  /** Sits in a fixed-width column so every label starts at the same x. */
  icon?: ReactNode;
  children: ReactNode;
  /**
   * A path to POST to, for a method that hands off to a provider. Never a
   * plain GET link: a GET /auth/:provider can be triggered on a victim's
   * session from an external page (CVE-2015-9284, see
   * config/initializers/omniauth.rb).
   */
  action?: string;
  onClick?: () => void;
};

export const AuthMethodButton = ({ icon, children, action, onClick, ...props }: Props) => {
  const button = (
    <Button
      type={action ? 'submit' : 'button'}
      variant="default"
      fullWidth
      onClick={onClick}
      leftSection={<span className={classes.icon}>{icon}</span>}
      classNames={{ root: classes.method }}
      {...props}
    >
      {children}
    </Button>
  );

  if (!action) return button;

  return (
    <form method="post" action={action} className={classes.form}>
      <input type="hidden" name="authenticity_token" value={getCsrfToken()} />
      {button}
    </form>
  );
};
