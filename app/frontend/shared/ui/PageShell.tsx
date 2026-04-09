import { Box, type BoxProps } from '@mantine/core';

import classes from './PageShell.module.css';

type PageShellVariant = 'default' | 'centered' | 'narrow';

interface PageShellProps extends BoxProps {
  variant?: PageShellVariant;
  /** When true, sets min-height: 100vh. Use false when nested inside AuthLayout. */
  fullPage?: boolean;
  maw?: number | string;
  children: React.ReactNode;
}

const VARIANT_CLASSES: Record<PageShellVariant, string> = {
  default: classes.default,
  centered: classes.centered,
  narrow: classes.narrow,
};

export const PageShell = ({
  variant = 'default',
  fullPage = true,
  maw,
  children,
  className,
  ...rest
}: PageShellProps) => (
  <Box
    className={`${classes.root} ${VARIANT_CLASSES[variant]} ${fullPage ? classes.fullPage : ''} ${className ?? ''}`}
    {...rest}
  >
    <Box className={classes.content} style={maw ? { maxWidth: maw } : undefined}>
      {children}
    </Box>
  </Box>
);
