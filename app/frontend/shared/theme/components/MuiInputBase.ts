import { Components, Theme } from '@mui/material';

import palette from '../baseTheme/palette';

export const MuiInputBase: Components<Theme>['MuiInputBase'] = {
  styleOverrides: {
    root: {
      color: palette.text.primaryFade,
      fontSize: '14px',
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
      '& textarea': {
        resize: 'vertical',
      },
    },
  },
};
