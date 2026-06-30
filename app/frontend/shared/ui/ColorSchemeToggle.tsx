import { Tooltip, UnstyledButton, useComputedColorScheme, useMantineColorScheme } from '@mantine/core';
import { IconMoon, IconSun } from '@tabler/icons-react';

interface ColorSchemeToggleProps {
  className?: string;
  size?: number;
  /** Tooltip side. Defaults to "right" (sidebar usage). */
  tooltipPosition?: 'top' | 'right' | 'bottom' | 'left';
}

/**
 * Switches between light and dark color schemes. The choice is persisted to
 * localStorage by Mantine's color-scheme manager (see application.tsx) and
 * re-applied before paint by the inline script in inertia.html.haml.
 */
export function ColorSchemeToggle({ className, size = 16, tooltipPosition = 'right' }: ColorSchemeToggleProps) {
  const { setColorScheme } = useMantineColorScheme();
  const computed = useComputedColorScheme('dark', { getInitialValueInEffect: true });
  const isDark = computed === 'dark';

  const toggle = () => setColorScheme(isDark ? 'light' : 'dark');
  const label = isDark ? 'Switch to light theme' : 'Switch to dark theme';

  return (
    <Tooltip label={label} position={tooltipPosition} withArrow>
      <UnstyledButton className={className} onClick={toggle} aria-label={label}>
        {isDark ? <IconSun size={size} /> : <IconMoon size={size} />}
      </UnstyledButton>
    </Tooltip>
  );
}
