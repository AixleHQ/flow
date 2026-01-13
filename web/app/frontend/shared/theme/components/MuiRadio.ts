import { Components, Theme } from '@mui/material';

export const MuiRadio: Components<Theme>['MuiRadio'] = {
  styleOverrides: {
    root: {
      color: '#FFFFFFCC',
      '&.Mui-disabled': {
        color: '#D9D9D929',
      },
    },
  },
};
