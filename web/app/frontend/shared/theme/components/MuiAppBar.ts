import { Components, Theme } from '@mui/material';

import palette from '../baseTheme/palette';

export const MuiAppBar: Components<Theme>['MuiAppBar'] = {
  styleOverrides: {
    root: {
      boxShadow: 'none',
      backgroundColor: 'transparent',
      borderBottomColor: palette.divider,
      borderBottomWidth: '1px',
      borderBottomStyle: 'solid',
    },
  },
};
