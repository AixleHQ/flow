import { Card, createTheme, type CSSVariablesResolver, type MantineColorsTuple } from '@mantine/core';

const blue: MantineColorsTuple = [
  '#e7f0ff',
  '#cddcfb',
  '#9bb6f3',
  '#6590ec',
  '#3B82F6', // [4] = main
  '#2570e4',
  '#1d66dc',
  '#1255c4',
  '#064bb0',
  '#003f9b',
];

const green: MantineColorsTuple = [
  '#e5fbed',
  '#cef5da',
  '#9eeab5',
  '#6bdf8c',
  '#22C55E', // [4] = main
  '#2db854',
  '#26a94a',
  '#1a953d',
  '#0d8534',
  '#007327',
];

const red: MantineColorsTuple = [
  '#ffe7e7',
  '#fecece',
  '#f99c9c',
  '#f46565',
  '#EF4444', // [4] = main
  '#ec2525',
  '#eb1414',
  '#d20707',
  '#bc0003',
  '#a40000',
];

const amber: MantineColorsTuple = [
  '#fff8e1',
  '#ffefcb',
  '#ffdd9a',
  '#ffcb64',
  '#F59E0B', // [4] = main
  '#f0a700',
  '#db9800',
  '#c08400',
  '#aa7500',
  '#906200',
];

const dark: MantineColorsTuple = [
  '#C1C2C5',
  '#A6A7AB',
  '#909296',
  '#5C5F66',
  '#373A40',
  '#2C2E33',
  '#1A1A1A',
  '#141414',
  '#0D0D0D',
  '#0A0A0A',
];

export const mantineTheme = createTheme({
  primaryColor: 'blue',
  colors: {
    blue,
    green,
    red,
    amber,
    dark,
  },

  fontFamily: 'Poppins, sans-serif',
  headings: { fontFamily: 'Poppins, sans-serif' },

  defaultRadius: 'md',

  other: {
    fontFamily: {
      body: 'Inter, sans-serif',
    },
    background: {
      default: '#0D0D0D',
      paper: '#141414',
      elevated: '#1A1A1A',
      deep: '#0A0A0A',
    },
    border: {
      default: '#2A2A2A',
      subtle: '#1F1F1F',
      strong: '#3A3A3A',
    },
    text: {
      primary: '#FFFFFF',
      secondary: '#A0A0A0',
      muted: '#666666',
    },
    action: {
      hover: 'rgba(255, 255, 255, 0.08)',
      selected: 'rgba(59, 130, 246, 0.16)',
    },
    status: {
      completed: '#22C55E',
      running: '#3B82F6',
      runningOther: '#F59E0B',
      pending: '#666666',
      error: '#EF4444',
    },
    agents: {
      codex: '#10A37F',
      cursor_cli: '#7C3AED',
      gemini_cli: '#3B82F6',
      claude_code: '#D97706',
    },
  },

  components: {
    Card: Card.extend({
      defaultProps: {
        bg: 'var(--app-bg-paper)',
      },
    }),
  },
});

export const cssVariablesResolver: CSSVariablesResolver = (theme) => ({
  variables: {
    '--app-font-body': theme.other.fontFamily.body,
    '--app-bg-default': theme.other.background.default,
    '--app-bg-paper': theme.other.background.paper,
    '--app-bg-elevated': theme.other.background.elevated,
    '--app-bg-deep': theme.other.background.deep,
    '--app-border-default': theme.other.border.default,
    '--app-border-subtle': theme.other.border.subtle,
    '--app-border-strong': theme.other.border.strong,
    '--app-text-primary': theme.other.text.primary,
    '--app-text-secondary': theme.other.text.secondary,
    '--app-text-muted': theme.other.text.muted,
    '--app-action-hover': theme.other.action.hover,
    '--app-action-selected': theme.other.action.selected,
  },
  light: {},
  dark: {},
});
