import { Box, BoxProps } from '@mui/material';

interface LogoProps extends Omit<BoxProps, 'component'> {
  width?: number | string;
  height?: number | string;
  variant?: 'full' | 'icon';
}

export const Logo = ({ width, height, variant = 'full', sx, ...props }: LogoProps) => {
  const defaultWidth = variant === 'icon' ? 32 : 120;
  const defaultHeight = variant === 'icon' ? 32 : undefined;

  return (
    <Box
      component="img"
      src="/logo.svg"
      alt="Palad"
      sx={{
        width: width || defaultWidth,
        height: height || defaultHeight,
        objectFit: 'contain',
        filter: 'brightness(0) invert(1)',
        ...sx,
      }}
      {...props}
    />
  );
};
