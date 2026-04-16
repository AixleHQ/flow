import { Image, type ImageProps } from '@mantine/core';

interface LogoProps extends Omit<ImageProps, 'src' | 'alt'> {
  width?: number | string;
  height?: number | string;
  variant?: 'full' | 'icon';
  colorScheme?: 'dark' | 'light';
}

export const Logo = ({ width, height, variant = 'full', colorScheme = 'dark', style, ...props }: LogoProps) => {
  const defaultWidth = variant === 'icon' ? 32 : 120;
  const defaultHeight = variant === 'icon' ? 32 : undefined;
  const filter = colorScheme === 'dark' ? 'brightness(0) invert(1)' : 'none';

  return (
    <Image
      src="/logo.svg"
      alt="Aixle"
      w={width || defaultWidth}
      h={height || defaultHeight}
      fit="contain"
      style={{ filter, ...style }}
      {...props}
    />
  );
};
