// The look every board chip's tooltip wears.
//
// Some chips on this board are deliberately tiny — a collapsed column's ticket is a 30×12 bar with
// no text at all, a CI gate is a badge holding one state word — and for those the tooltip is not a
// hint, it is where the content lives. They should therefore not look like two different
// mechanisms: dark, arrowed, and anchored to the right of the chip it belongs to.
//
// Spread this into `<Tooltip>`; a caller adds only what is specific to its own content (a
// `multiline` width for a tooltip that carries a sentence rather than a line).
export const CHIP_TOOLTIP_PROPS = {
  position: 'right',
  withArrow: true,
  color: 'dark',
} as const;
