import { Card, Input, createTheme, type CSSVariablesResolver, type MantineColorsTuple } from '@mantine/core';

const accentBlue: MantineColorsTuple = [
  'rgba(122,162,200,0.05)', // 0 — hover
  'rgba(122,162,200,0.08)', // 1
  'rgba(122,162,200,0.10)', // 2 — active / dim
  'rgba(122,162,200,0.16)', // 3 — mid
  'rgba(122,162,200,0.28)', // 4 — muted border
  '#7aa2c8', // 5 — base accent ← primaryShade
  '#6892b8', // 6
  '#5a82a8', // 7
  '#3a6288', // 8
  '#2a4a68', // 9
];

const dark: MantineColorsTuple = [
  '#e8edf2', // 0 — text-1
  '#96a0a8', // 1 — text-2
  '#586470', // 2 — text-3
  '#253040', // 3 — border-mid
  '#1e2c3c', // 4 — border
  '#1c2838', // 5 — raised cards
  '#131c24', // 6 — bg-card
  '#141c26', // 7 — surface / sidebar
  '#0d1117', // 8 — page bg
  '#080e14', // 9 — deepest
];

export const mantineTheme = createTheme({
  fontFamily: 'Inter, sans-serif',
  fontFamilyMonospace: 'Geist Mono, monospace',

  primaryColor: 'accentBlue',
  primaryShade: { light: 5, dark: 5 },
  colors: { accentBlue, dark },

  headings: {
    fontFamily: 'Sora, sans-serif',
    fontWeight: '700',
  },

  defaultRadius: 'md',
  focusRing: 'auto',
  cursorType: 'pointer',

  components: {
    Button: { defaultProps: { radius: 'md', size: 'sm' } },
    Input: Input.extend({
      defaultProps: { radius: 'md', size: 'sm' },
      styles: {
        input: {
          backgroundColor: 'var(--app-bg-default)',
          borderColor: 'var(--app-border-strong)',
          color: 'var(--app-text-primary)',
        },
      },
    }),
    TextInput: { defaultProps: { radius: 'md', size: 'sm' } },
    Select: { defaultProps: { radius: 'md', size: 'sm' } },
    Textarea: { defaultProps: { radius: 'md', size: 'sm' } },
    Badge: { defaultProps: { radius: 'sm', size: 'sm' } },
    Tooltip: { defaultProps: { radius: 'sm' } },
    Modal: { defaultProps: { radius: 'lg' } },
    Menu: { defaultProps: { radius: 'md' } },
    Tabs: { defaultProps: { radius: 'sm' } },
    Card: Card.extend({
      defaultProps: {
        bg: 'var(--app-bg-paper)',
      },
    }),
  },
});

export const cssVariablesResolver: CSSVariablesResolver = () => ({
  variables: {
    '--app-font-body': 'Inter, sans-serif',
    '--app-bg-default': '#0d1117',
    '--app-bg-paper': '#141c26',
    '--app-bg-elevated': '#131c24',
    '--app-bg-deep': '#080e14',
    '--app-border-default': '#1e2c3c',
    '--app-border-subtle': '#141c26',
    '--app-border-strong': '#253040',
    '--app-text-primary': '#e8edf2',
    '--app-text-secondary': '#96a0a8',
    '--app-text-tertiary': '#586470',
    '--app-action-hover': 'rgba(122,162,200,0.05)',
    '--app-action-selected': 'rgba(122,162,200,0.10)',
  },
  light: {},
  dark: {
    /* Mantine internal input/form variables */
    '--mantine-color-default': '#0d1117',
    '--mantine-color-default-border': '#253040',
    '--mantine-color-default-hover': '#141c26',
    '--mantine-color-default-color': '#e8edf2',
    '--mantine-color-default-color-hover': '#e8edf2',
    '--mantine-color-placeholder': '#586470',
    /* Brighter icon color for Select/Input right-section chevrons */
    '--mantine-color-dimmed': '#96a0a8',
    /* Fix "light" variant — Mantine's dark-scheme auto-generated tints are near-invisible */
    '--mantine-color-accentBlue-light': 'rgba(122,162,200,0.15)',
    '--mantine-color-accentBlue-light-hover': 'rgba(122,162,200,0.22)',
    '--mantine-color-accentBlue-light-color': '#7aa2c8',
    '--mantine-color-red-light': 'rgba(255,100,100,0.15)',
    '--mantine-color-red-light-hover': 'rgba(255,100,100,0.22)',
    '--mantine-color-red-light-color': '#ff6b6b',
    '--mantine-color-green-light': 'rgba(82,196,120,0.15)',
    '--mantine-color-green-light-hover': 'rgba(82,196,120,0.22)',
    '--mantine-color-green-light-color': '#52c478',
    '--mantine-color-orange-light': 'rgba(255,160,64,0.15)',
    '--mantine-color-orange-light-hover': 'rgba(255,160,64,0.22)',
    '--mantine-color-orange-light-color': '#ffa040',
    '--mantine-color-yellow-light': 'rgba(255,208,64,0.15)',
    '--mantine-color-yellow-light-hover': 'rgba(255,208,64,0.22)',
    '--mantine-color-yellow-light-color': '#ffd040',
    '--mantine-color-teal-light': 'rgba(56,201,183,0.15)',
    '--mantine-color-teal-light-hover': 'rgba(56,201,183,0.22)',
    '--mantine-color-teal-light-color': '#38c9b7',
    '--mantine-color-gray-light': 'rgba(148,160,172,0.12)',
    '--mantine-color-gray-light-hover': 'rgba(148,160,172,0.18)',
    '--mantine-color-gray-light-color': '#94a0ac',
    '--mantine-color-blue-light': 'rgba(77,171,247,0.15)',
    '--mantine-color-blue-light-hover': 'rgba(77,171,247,0.22)',
    '--mantine-color-blue-light-color': '#4dabf7',
    '--mantine-color-dark-light': 'rgba(37,48,64,0.50)',
    '--mantine-color-dark-light-hover': 'rgba(37,48,64,0.70)',
    '--mantine-color-dark-light-color': '#96a0a8',
    /* Fix "outline" variant — border uses filled color, text matches */
    '--mantine-color-accentBlue-outline': '#7aa2c8',
    '--mantine-color-accentBlue-outline-hover': 'rgba(122,162,200,0.08)',
    '--mantine-color-red-outline': '#ff6b6b',
    '--mantine-color-red-outline-hover': 'rgba(255,100,100,0.08)',
    '--mantine-color-green-outline': '#52c478',
    '--mantine-color-green-outline-hover': 'rgba(82,196,120,0.08)',
    '--mantine-color-orange-outline': '#ffa040',
    '--mantine-color-orange-outline-hover': 'rgba(255,160,64,0.08)',
    '--mantine-color-yellow-outline': '#ffd040',
    '--mantine-color-yellow-outline-hover': 'rgba(255,208,64,0.08)',
    '--mantine-color-blue-outline': '#4dabf7',
    '--mantine-color-blue-outline-hover': 'rgba(77,171,247,0.08)',
    '--mantine-color-gray-outline': '#94a0ac',
    '--mantine-color-gray-outline-hover': 'rgba(148,160,172,0.08)',
    '--mantine-color-grape-outline': '#da77f2',
    '--mantine-color-grape-outline-hover': 'rgba(218,119,242,0.08)',
    '--mantine-color-cyan-outline': '#66d9e8',
    '--mantine-color-cyan-outline-hover': 'rgba(102,217,232,0.08)',
    /* Fix "subtle" variant — no bg by default, hover shows tint, text = accent color */
    '--mantine-color-accentBlue-subtle': 'transparent',
    '--mantine-color-accentBlue-subtle-hover': 'rgba(122,162,200,0.10)',
    '--mantine-color-accentBlue-subtle-color': '#7aa2c8',
    '--mantine-color-red-subtle': 'transparent',
    '--mantine-color-red-subtle-hover': 'rgba(255,100,100,0.10)',
    '--mantine-color-red-subtle-color': '#ff6b6b',
    '--mantine-color-gray-subtle': 'transparent',
    '--mantine-color-gray-subtle-hover': 'rgba(148,160,172,0.10)',
    '--mantine-color-gray-subtle-color': '#94a0ac',
  },
});
