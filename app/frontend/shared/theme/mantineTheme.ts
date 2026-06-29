import { Card, Input, createTheme, type CSSVariablesResolver, type MantineColorsTuple } from '@mantine/core';

/**
 * Brand accent — Aixle orange (#E0582E). Single accent, used with intent.
 * Ramp goes light → dark; base brand orange sits at shade 6, the brighter
 * hover tone at shade 5, the darker press tone at shade 7.
 */
const brand: MantineColorsTuple = [
  '#fdeee8', // 0 — lightest tint
  '#f9d8cc', // 1
  '#f2b49e', // 2
  '#ec8f6d', // 3
  '#e97a50', // 4
  '#e66339', // 5 — hover (bright, used as dark-scheme primary)
  '#e0582e', // 6 — base accent (Aixle orange) ← light primaryShade
  '#c44a24', // 7 — press (darker, accessible on white)
  '#a23c1d', // 8
  '#7e2e16', // 9
];

/**
 * Neutral scale — Aixle warm near-black ramp (off-white → black).
 * Mapped onto Mantine's `dark` tuple indices: 0 = lightest text,
 * 7 = body/page background, 9 = deepest.
 */
const dark: MantineColorsTuple = [
  '#d1cfcd', // 0 — text-1 (off-white, Aixle fg)
  '#9f9d9c', // 1 — text-2
  '#7f7e7c', // 2 — text-3 / subtle
  '#5d5b5a', // 3 — disabled
  '#393837', // 4 — border-strong
  '#292726', // 5 — border / hairline
  '#191817', // 6 — surface (sidebar, panels)
  '#0a0908', // 7 — page background (Aixle black)
  '#070605', // 8
  '#040302', // 9 — deepest
];

export const mantineTheme = createTheme({
  fontFamily: 'Figtree, sans-serif',
  fontFamilyMonospace: '"JetBrains Mono", monospace',

  primaryColor: 'brand',
  // Dark: brand orange (6). Light: darker press tone (7) so white text on
  // filled buttons clears WCAG AA contrast on a white canvas.
  primaryShade: { light: 7, dark: 6 },
  colors: { brand, dark },

  headings: {
    // Aixle uses Lab Grotesque (→ Hanken Grotesk) at regular-ish weight; size and
    // tight tracking carry the headlines rather than heavy bold.
    fontFamily: '"Hanken Grotesk", sans-serif',
    fontWeight: '500',
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

/**
 * Semantic `--app-*` tokens. These are the app's theming contract — every
 * surface/border/text color in pages and CSS modules should reference one of
 * these so it adapts between schemes automatically.
 *
 * Dark  = Aixle warm near-black palette.
 * Light = GitHub-Primer-like neutrals with the same orange accent.
 */
export const cssVariablesResolver: CSSVariablesResolver = () => ({
  variables: {
    /* Aixle typography — body Figtree, headings Hanken Grotesk, code JetBrains Mono,
       small decorative mono labels Spline Sans Mono. */
    '--app-font-body': 'Figtree, sans-serif',
    '--app-font-heading': '"Hanken Grotesk", sans-serif',
    '--app-font-mono': '"JetBrains Mono", monospace',
    '--app-font-mono-label': '"Spline Sans Mono", monospace',
  },

  light: {
    /* App semantic tokens — GitHub-like light */
    '--app-bg-default': '#ffffff',
    '--app-bg-paper': '#ffffff',
    '--app-bg-elevated': '#f6f8fa',
    '--app-bg-deep': '#f6f8fa',
    '--app-border-default': '#d1d9e0',
    '--app-border-subtle': '#eaeef2',
    '--app-border-strong': '#afb8c1',
    '--app-text-primary': '#1f2328',
    '--app-text-secondary': '#59636e',
    '--app-text-tertiary': '#818b98',
    '--app-action-hover': 'rgba(208,215,222,0.32)',
    '--app-action-selected': 'rgba(224,88,46,0.12)',

    /* Mantine internal input/form variables — GitHub light */
    '--mantine-color-text': '#1f2328',
    '--mantine-color-body': '#ffffff',
    '--mantine-color-default': '#ffffff',
    '--mantine-color-default-border': '#d1d9e0',
    '--mantine-color-default-hover': '#f6f8fa',
    '--mantine-color-default-color': '#1f2328',
    '--mantine-color-placeholder': '#818b98',
    '--mantine-color-dimmed': '#59636e',

    /* brand variants tuned for a light canvas */
    '--mantine-color-brand-light': 'rgba(224,88,46,0.10)',
    '--mantine-color-brand-light-hover': 'rgba(224,88,46,0.16)',
    '--mantine-color-brand-light-color': '#c44a24',
    '--mantine-color-brand-outline': '#c44a24',
    '--mantine-color-brand-outline-hover': 'rgba(224,88,46,0.06)',
    '--mantine-color-brand-subtle': 'transparent',
    '--mantine-color-brand-subtle-hover': 'rgba(224,88,46,0.10)',
    '--mantine-color-brand-subtle-color': '#c44a24',
  },

  dark: {
    /* App semantic tokens — Aixle warm near-black */
    '--app-bg-default': '#0a0908',
    '--app-bg-paper': '#191817',
    '--app-bg-elevated': '#1c1a18',
    '--app-bg-deep': '#050403',
    '--app-border-default': '#292726',
    '--app-border-subtle': '#1c1a18',
    '--app-border-strong': '#393837',
    '--app-text-primary': '#d1cfcd',
    '--app-text-secondary': '#9f9d9c',
    '--app-text-tertiary': '#7f7e7c',
    '--app-action-hover': 'rgba(209,207,205,0.05)',
    '--app-action-selected': 'rgba(224,88,46,0.12)',

    /* Mantine internal input/form variables */
    '--mantine-color-text': '#d1cfcd',
    '--mantine-color-body': '#0a0908',
    '--mantine-color-default': '#0a0908',
    '--mantine-color-default-border': '#393837',
    '--mantine-color-default-hover': '#191817',
    '--mantine-color-default-color': '#d1cfcd',
    '--mantine-color-default-color-hover': '#d1cfcd',
    '--mantine-color-placeholder': '#7f7e7c',
    /* Brighter icon color for Select/Input right-section chevrons */
    '--mantine-color-dimmed': '#9f9d9c',
    /* Fix "light" variant — Mantine's dark-scheme auto-generated tints are near-invisible */
    '--mantine-color-brand-light': 'rgba(224,88,46,0.15)',
    '--mantine-color-brand-light-hover': 'rgba(224,88,46,0.22)',
    '--mantine-color-brand-light-color': '#e0582e',
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
    '--mantine-color-dark-light': 'rgba(41,39,38,0.50)',
    '--mantine-color-dark-light-hover': 'rgba(41,39,38,0.70)',
    '--mantine-color-dark-light-color': '#9f9d9c',
    /* Fix "outline" variant — border uses filled color, text matches */
    '--mantine-color-brand-outline': '#e0582e',
    '--mantine-color-brand-outline-hover': 'rgba(224,88,46,0.08)',
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
    '--mantine-color-brand-subtle': 'transparent',
    '--mantine-color-brand-subtle-hover': 'rgba(224,88,46,0.10)',
    '--mantine-color-brand-subtle-color': '#e0582e',
    '--mantine-color-red-subtle': 'transparent',
    '--mantine-color-red-subtle-hover': 'rgba(255,100,100,0.10)',
    '--mantine-color-red-subtle-color': '#ff6b6b',
    '--mantine-color-gray-subtle': 'transparent',
    '--mantine-color-gray-subtle-hover': 'rgba(148,160,172,0.10)',
    '--mantine-color-gray-subtle-color': '#94a0ac',
  },
});
