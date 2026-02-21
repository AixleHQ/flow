import { Box, BoxProps } from '@mui/material';

interface LogoProps extends Omit<BoxProps, 'component'> {
  width?: number | string;
  height?: number | string;
  variant?: 'full' | 'icon';
  colorScheme?: 'dark' | 'light';
}

export const Logo = ({ width, height, variant = 'full', colorScheme = 'dark', sx, ...props }: LogoProps) => {
  const defaultWidth = variant === 'icon' ? 32 : 120;
  const defaultHeight = variant === 'icon' ? 32 : undefined;

  // Apply filter only for dark color scheme (white logo on dark background)
  const filter = colorScheme === 'dark' ? 'brightness(0) invert(1)' : 'none';

  return (
    <Box
      component="img"
      src="/logo.svg"
      alt="Palad"
      sx={{
        width: width || defaultWidth,
        height: height || defaultHeight,
        objectFit: 'contain',
        filter,
        ...sx,
      }}
      {...props}
    />
  );
};
