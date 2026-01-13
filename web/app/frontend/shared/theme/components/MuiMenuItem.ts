import { Components, Theme } from '@mui/material';

export const MuiMenuItem: Components<Theme>['MuiMenuItem'] = {
  styleOverrides: {
    root: {
      paddingLeft: '24px',
      paddingRight: '24px',
      paddingTop: '12px',
      paddingBottom: '12px',
      color: '#DFE1E5',
      fontSize: 16,
      fontWeight: 500,
      lineHeight: '24px',
    },
  },
};
