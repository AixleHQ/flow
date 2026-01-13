import { Components, Theme } from '@mui/material';

export const MuiButtonGroup: Components<Theme>['MuiButtonGroup'] = {
  styleOverrides: {
    root: {
      boxShadow: 'none',
      '&:hover': {
        boxShadow: '0px 4px 12px 0px #0037A352',
        '& > .MuiButtonGroup-firstButton:hover': {
          borderColor: 'rgba(95, 120, 255, 0.24)',
        },
      },
    },
  },
};
