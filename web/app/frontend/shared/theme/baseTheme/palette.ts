// Palad Design System - Dark Theme
// Based on UX Design Specification

export default {
  // Background layers (darkest to lightest)
  background: {
    default: '#0D0D0D', // bg.primary - main background
    paper: '#141414', // bg.secondary - cards, panels
    elevated: '#1A1A1A', // bg.tertiary - elevated surfaces
    dark: '#0A0A0A', // bg.deep - terminal, code areas
    gradient: 'linear-gradient(180deg, rgba(59, 130, 246, 0.05) 0%, rgba(13, 13, 13, 1) 100%)',
    // UX Spec colors for login/public pages
    base: '#09090B', // Page background (UX Spec)
    surface: '#18181B', // Cards, panels (UX Spec)
    elevatedAlt: '#27272A', // Hover, selected (UX Spec)
  },

  // Primary accent (blue)
  primary: {
    main: '#3B82F6', // accent.blue
    light: '#60A5FA',
    dark: '#2563EB',
    contrastText: '#FFFFFF',
  },

  // Secondary accent (green for success/costs)
  secondary: {
    main: '#22C55E', // accent.green
    light: '#4ADE80',
    dark: '#16A34A',
    contrastText: '#FFFFFF',
  },

  // Status colors
  success: {
    main: '#22C55E', // accent.green
    light: '#4ADE80',
    dark: '#16A34A',
  },
  warning: {
    main: '#F59E0B', // accent.amber
    light: '#FBBF24',
    dark: '#D97706',
  },
  error: {
    main: '#EF4444', // accent.red
    light: '#F87171',
    dark: '#DC2626',
  },
  info: {
    main: '#3B82F6', // accent.blue
    light: '#60A5FA',
    dark: '#2563EB',
  },

  // Text hierarchy
  text: {
    primary: '#FFFFFF', // text.primary
    secondary: '#A0A0A0', // text.secondary
    disabled: '#666666', // text.muted
    primaryFade: 'rgba(255, 255, 255, 0.72)',
    // UX Spec text colors
    primaryAlt: '#D4D4D8', // Main text (UX Spec)
    secondaryAlt: '#A1A1AA', // Secondary text (UX Spec)
    muted: '#52525B', // Disabled, hints (UX Spec)
  },

  // Borders and dividers
  divider: '#2A2A2A', // border.default
  border: {
    default: '#2A2A2A',
    subtle: '#1F1F1F',
    strong: '#3A3A3A',
    focus: '#3B82F6', // accent.blue for focus states
    // UX Spec border color
    defaultAlt: '#3F3F46', // Borders, dividers (UX Spec)
  },

  // Action colors (for buttons, interactive elements)
  action: {
    active: '#FFFFFF',
    hover: 'rgba(255, 255, 255, 0.08)',
    selected: 'rgba(59, 130, 246, 0.16)',
    disabled: 'rgba(255, 255, 255, 0.3)',
    disabledBackground: 'rgba(255, 255, 255, 0.12)',
    focus: 'rgba(59, 130, 246, 0.24)',
  },

  // Agent colors (for session indicators)
  agents: {
    codex: '#10A37F',
    cursor_cli: '#7C3AED',
    open_code: '#3B82F6',
    claude_code: '#D97706',
  },

  // Status indicators
  status: {
    completed: '#22C55E', // green
    running: '#3B82F6', // blue (mine)
    runningOther: '#F59E0B', // amber (other user)
    pending: '#666666', // gray
    error: '#EF4444', // red
  },

  // Legacy support (for existing components)
  button: {
    gradient: 'linear-gradient(180deg, #1A1A1A 0%, #141414 100%)',
  },
};
