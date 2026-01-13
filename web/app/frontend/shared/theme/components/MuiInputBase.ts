import { Components, Theme } from '@mui/material';

import palette from '../baseTheme/palette';

export const MuiInputBase: Components<Theme>['MuiInputBase'] = {
  styleOverrides: {
    root: {
      background: palette.background.gradient,
      border: `1px solid ${palette.border}`,
      color: palette.text.primaryFade,
      height: '40px',
      '&.Mui-disabled': {
        opacity: 0.5,
        '& input': {
          color: 'rgba(255, 255, 255, 0.3) !important',
          WebkitTextFillColor: 'rgba(255, 255, 255, 0.3) !important',
        },
        '& textarea': {
          color: 'rgba(255, 255, 255, 0.3) !important',
          WebkitTextFillColor: 'rgba(255, 255, 255, 0.3) !important',
        },
      },
    },
    input: {
      '&.Mui-disabled': {
        color: 'rgba(255, 255, 255, 0.3) !important',
        WebkitTextFillColor: 'rgba(255, 255, 255, 0.3) !important',
      },
    },
    multiline: {
      height: 'auto',
      minHeight: '40px',
    },
  },
};
