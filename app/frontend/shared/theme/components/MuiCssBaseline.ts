import { Components, Theme } from '@mui/material';

export const MuiCssBaseline: Components<Theme>['MuiCssBaseline'] = {
  styleOverrides: {
    html: {
      scrollBehavior: 'smooth',
    },
  },
};
