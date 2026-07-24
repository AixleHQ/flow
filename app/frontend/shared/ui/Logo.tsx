import { Image, type ImageProps } from '@mantine/core';
import { useComputedColorScheme } from '@mantine/core';

interface LogoProps extends Omit<ImageProps, 'src' | 'alt'> {
  width?: number | string;
  height?: number | string;
  variant?: 'full' | 'icon';
  colorScheme?: 'dark' | 'light';
}

export const Logo = ({ width, height, variant = 'full', colorScheme, style, ...props }: LogoProps) => {
  const computedScheme = useComputedColorScheme('dark');
  const resolvedScheme = colorScheme ?? computedScheme;
  const defaultWidth = variant === 'icon' ? 32 : 120;
  const defaultHeight = variant === 'icon' ? 32 : undefined;
  const filter = resolvedScheme === 'dark' ? 'brightness(0) invert(1)' : 'none';

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
