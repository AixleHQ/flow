import { Button, Card, Input, createTheme, type CSSVariablesResolver, type MantineColorsTuple } from '@mantine/core';

import inputClasses from './inputs.module.css';

/**
 * Brand accent — Aixle terracotta (#CF6B4A) — a desaturated tone of the brand orange (#E0582E),
 * calmer in dense UI. Single accent, used with intent.
 * Ramp goes light → dark; base brand orange sits at shade 6, the brighter
 * hover tone at shade 5, the darker press tone at shade 7.
 */
const brand: MantineColorsTuple = [
  '#f8e8e2', // 0 — lightest tint
  '#efcec3', // 1
  '#e3a996', // 2
  '#dd967e', // 3
  '#db8f76', // 4
  '#d78569', // 5 — hover (bright, used as dark-scheme primary)
  '#cf6b4a', // 6 — base accent (Aixle orange) ← light primaryShade
  '#b95331', // 7 — press (darker, accessible on white)
  '#994529', // 8
  '#793620', // 9
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

  // Filled controls pick their label color from the fill's luminance instead of
  // always using white. White on the dark-scheme orange (#cf6b4a) measures
  // 3.59:1 — below AA. Near-black on the same fill measures 5.55:1, and white
  // on the light-scheme press tone (#b95331) measures 4.83:1. The threshold has
  // to sit between those two luminances for both to resolve correctly.
  autoContrast: true,
  luminanceThreshold: 0.2,

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
    // Filled brand buttons: pin the label color. `autoContrast` alone left the
    // default filled Button rendering white on the dark-scheme orange (3.59:1,
    // verified in-browser); --app-on-primary is near-black there (5.55:1) and
    // white on the light-scheme press tone (4.83:1). Only the brand default is
    // touched — white stays correct on red/green/etc.
    Button: Button.extend({
      defaultProps: { radius: 'md', size: 'sm' },
      vars: (_theme, props) => {
        const isBrandFilled =
          (!props.color || props.color === 'brand') && (!props.variant || props.variant === 'filled');
        return { root: isBrandFilled ? { '--button-color': 'var(--app-on-primary)' } : {} };
      },
    }),
    // `classNames`, not `styles` — see the comment in inputs.module.css.
    Input: Input.extend({
      defaultProps: { radius: 'md', size: 'sm' },
      classNames: { input: inputClasses.input },
    }),
    TextInput: { defaultProps: { radius: 'md', size: 'sm' } },
    Select: { defaultProps: { radius: 'md', size: 'sm' } },
    Textarea: { defaultProps: { radius: 'md', size: 'sm' } },
    Badge: { defaultProps: { radius: 'sm', size: 'sm' } },
    Tooltip: { defaultProps: { radius: 'sm' } },
    // Mantine's internal clear/remove buttons (input clear button, MultiSelect
    // pill remove) render a bare CloseButton with no accessible name.
    CloseButton: { defaultProps: { 'aria-label': 'Clear' } },
    Modal: { defaultProps: { radius: 'lg' } },
    Menu: { defaultProps: { radius: 'md' } },
    Tabs: { defaultProps: { radius: 'sm' } },
    // Light mode sets --app-bg-paper and --app-bg-default to the same white, so
    // an unbordered card has no boundary at all on a light canvas. The border
    // is what separates surfaces there; dark mode separates them by value and
    // the same hairline just reinforces it.
    Card: Card.extend({
      defaultProps: {
        bg: 'var(--app-bg-paper)',
        withBorder: true,
      },
      styles: {
        root: { borderColor: 'var(--app-border-default)' },
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
    /* Terminal surfaces are black in both schemes — xterm draws the agent's own
       ANSI palette against them. */
    '--app-terminal-bg': '#000000',

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
    '--app-bg-card': '#ffffff',
    '--app-bg-elevated': '#f6f8fa',
    '--app-bg-deep': '#f6f8fa',
    '--app-bg-hover': 'rgba(208,215,222,0.32)',
    '--heatmap-cell-empty': '#eaeef2',
    '--app-accent': '#cf6b4a',
    '--app-chart-taupe': '#8a8078',
    '--app-taupe-dim': 'rgba(138,128,120,0.14)',
    '--app-a-cursor': '#d2a878',
    '--app-a-gemini': '#6f5a4e',
    '--app-border-default': '#d1d9e0',
    '--app-border-subtle': '#eaeef2',
    '--app-border-strong': '#afb8c1',
    '--app-border-active': '#b95331',
    '--app-text-primary': '#1f2328',
    '--app-text-secondary': '#59636e',
    /* #818b98 measured 3.45:1 on white — below AA, and it is the color of the
       sidebar group labels and the user name on every page. Primer's fg.muted
       clears 4.5:1. */
    /* Clears 4.5:1 on the tinted --app-bg-deep (#f6f8fa) as well as on white —
       docs chrome sits on the tint, where #6e7781 measured 4.27. */
    '--app-text-tertiary': '#68717b',
    '--app-action-hover': 'rgba(208,215,222,0.32)',
    '--app-action-selected': 'rgba(207,107,74,0.12)',
    '--app-primary': '#b95331',
    /* Accent TEXT sitting on an --app-action-selected tint. --app-primary on
       that tint is 4.22:1 in light; this clears AA on both tint and canvas.
       Use --app-primary for fills and borders, this for type and icons. */
    '--app-primary-strong': '#8a3d23',
    /* Alias a CSS module referenced before it existed (--app-accent is already
       defined above, for the heatmap ramp). */
    '--app-border': '#d1d9e0',
    /* Inverted CTA (the sidebar "Build with AI" pill) — used to be inline
       dark-scheme literals, which rendered grey-on-white in light mode. */
    '--app-cta-invert-bg': '#1f2328',
    '--app-cta-invert-bg-hover': '#32383f',
    '--app-cta-invert-fg': '#ffffff',
    /* Status tokens — badges and callouts used raw Mantine colors that fail AA
       on a light canvas at badge sizes. */
    /* Each foreground is picked to clear 4.5:1 against its OWN tinted
       background, not just against white — status text almost always sits on
       the matching *-bg, and Primer's own fg values land at 4.2-4.4 there. */
    '--app-success-fg': '#14682c',
    '--app-success-bg': 'rgba(26,127,55,0.10)',
    '--app-success-border': 'rgba(26,127,55,0.30)',
    '--app-warning-fg': '#7d5400',
    '--app-warning-bg': 'rgba(154,103,0,0.10)',
    '--app-warning-border': 'rgba(154,103,0,0.30)',
    '--app-danger-fg': '#b31c27',
    '--app-danger-bg': 'rgba(207,34,46,0.10)',
    '--app-danger-border': 'rgba(207,34,46,0.30)',
    '--app-info-fg': '#0757b3',
    '--app-info-bg': 'rgba(9,105,218,0.10)',
    '--app-info-border': 'rgba(9,105,218,0.30)',
    '--app-tip-fg': '#6340b8',
    '--app-tip-bg': 'rgba(124,92,214,0.10)',
    '--app-tip-border': 'rgba(124,92,214,0.30)',
    /* Categorical chart ramp, anchored on the brand and matched for luminance
       on a light canvas. Replaces the hardcoded Material 500 palette. */
    '--app-chart-1': '#b95331',
    '--app-chart-2': '#1f6feb',
    '--app-chart-3': '#2f8f4e',
    '--app-chart-4': '#a4741a',
    '--app-chart-5': '#7c5cd6',
    '--app-chart-6': '#0f8b81',
    '--app-chart-7': '#c14a72',
    /* Warm neutral ramp for agent series. Identity on those charts is carried by
       the logo and label; colour is a secondary cue, so the ramp stays quiet and
       reads the same in both schemes. */
    '--app-chart-warm-1': '#8a8078',
    '--app-chart-warm-2': '#d2a878',
    '--app-chart-warm-3': '#6f5a4e',
    /* Contribution-heatmap intensity ramp — was GitHub's exact greens. */
    /* Label color on a --app-primary fill. Pinned rather than left to
       autoContrast, which measured as still emitting white on the dark-scheme
       orange. White on #b95331 = 4.83:1. */
    '--mantine-color-brand-contrast': '#ffffff',
    '--app-on-primary': '#ffffff',
    '--app-accent-muted': 'rgba(185,83,49,0.25)',

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
    '--mantine-color-brand-light': 'rgba(207,107,74,0.10)',
    '--mantine-color-brand-light-hover': 'rgba(207,107,74,0.16)',
    '--mantine-color-brand-light-color': '#b95331',
    '--mantine-color-brand-outline': '#b95331',
    '--mantine-color-brand-outline-hover': 'rgba(207,107,74,0.06)',
    '--mantine-color-brand-subtle': 'transparent',
    '--mantine-color-brand-subtle-hover': 'rgba(207,107,74,0.10)',
    '--mantine-color-brand-subtle-color': '#b95331',
  },

  dark: {
    /* App semantic tokens — Aixle warm near-black */
    '--app-bg-default': '#0a0908',
    '--app-bg-paper': '#191817',
    '--app-bg-card': '#121110',
    '--app-bg-elevated': '#1c1a18',
    '--app-bg-deep': '#050403',
    '--app-bg-hover': 'rgba(209,207,205,0.05)',
    '--heatmap-cell-empty': '#191817',
    '--app-accent': '#cf6b4a',
    '--app-chart-taupe': '#8a8078',
    '--app-taupe-dim': 'rgba(138,128,120,0.14)',
    '--app-a-cursor': '#d2a878',
    '--app-a-gemini': '#6f5a4e',
    '--app-border-default': '#292726',
    '--app-border-subtle': '#1c1a18',
    '--app-border-strong': '#393837',
    '--app-border-active': '#cf6b4a',
    '--app-text-primary': '#d1cfcd',
    '--app-text-secondary': '#9f9d9c',
    /* #7f7e7c measured 4.37:1 on --app-bg-paper — just under AA, on chrome that
       appears on every page. */
    '--app-text-tertiary': '#8b8987',
    '--app-action-hover': 'rgba(209,207,205,0.05)',
    '--app-action-selected': 'rgba(207,107,74,0.12)',
    '--app-primary': '#cf6b4a',
    /* See the light block: accent type on an --app-action-selected tint. */
    '--app-primary-strong': '#e08a6c',
    '--app-border': '#292726',
    '--app-cta-invert-bg': '#d1cfcd',
    '--app-cta-invert-bg-hover': '#e6e4e2',
    '--app-cta-invert-fg': '#0a0908',
    '--app-success-fg': '#52c478',
    '--app-success-bg': 'rgba(82,196,120,0.15)',
    '--app-success-border': 'rgba(82,196,120,0.35)',
    '--app-warning-fg': '#ffb35c',
    '--app-warning-bg': 'rgba(255,160,64,0.15)',
    '--app-warning-border': 'rgba(255,160,64,0.35)',
    '--app-danger-fg': '#ff6b6b',
    '--app-danger-bg': 'rgba(255,100,100,0.15)',
    '--app-danger-border': 'rgba(255,100,100,0.35)',
    '--app-info-fg': '#4dabf7',
    '--app-info-bg': 'rgba(77,171,247,0.15)',
    '--app-info-border': 'rgba(77,171,247,0.35)',
    '--app-tip-fg': '#a78bfa',
    '--app-tip-bg': 'rgba(167,139,250,0.15)',
    '--app-tip-border': 'rgba(167,139,250,0.35)',
    '--app-chart-1': '#cf6b4a',
    '--app-chart-2': '#4dabf7',
    '--app-chart-3': '#52c478',
    '--app-chart-4': '#e6b45e',
    '--app-chart-5': '#a78bfa',
    '--app-chart-6': '#38c9b7',
    '--app-chart-7': '#f2789f',
    /* Warm neutral ramp for agent series. Identity on those charts is carried by
       the logo and label; colour is a secondary cue, so the ramp stays quiet and
       reads the same in both schemes. */
    '--app-chart-warm-1': '#8a8078',
    '--app-chart-warm-2': '#d2a878',
    '--app-chart-warm-3': '#6f5a4e',
    /* Near-black on #cf6b4a = 5.55:1; white would be 3.59:1. */
    '--mantine-color-brand-contrast': '#0a0908',
    '--app-on-primary': '#0a0908',
    '--app-accent-muted': 'rgba(207,107,74,0.30)',

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
    '--mantine-color-brand-light': 'rgba(207,107,74,0.15)',
    '--mantine-color-brand-light-hover': 'rgba(207,107,74,0.22)',
    '--mantine-color-brand-light-color': '#cf6b4a',
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
    '--mantine-color-brand-outline': '#cf6b4a',
    '--mantine-color-brand-outline-hover': 'rgba(207,107,74,0.08)',
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
    '--mantine-color-brand-subtle-hover': 'rgba(207,107,74,0.10)',
    '--mantine-color-brand-subtle-color': '#cf6b4a',
    '--mantine-color-red-subtle': 'transparent',
    '--mantine-color-red-subtle-hover': 'rgba(255,100,100,0.10)',
    '--mantine-color-red-subtle-color': '#ff6b6b',
    '--mantine-color-gray-subtle': 'transparent',
    '--mantine-color-gray-subtle-hover': 'rgba(148,160,172,0.10)',
    '--mantine-color-gray-subtle-color': '#94a0ac',
  },
});
