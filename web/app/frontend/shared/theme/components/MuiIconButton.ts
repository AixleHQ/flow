import { Components, Theme } from '@mui/material';

export const MuiIconButton: Components<Theme>['MuiIconButton'] = {
  styleOverrides: {
    root: {
      '&.Mui-disabled': {
        color: 'rgba(255, 255, 255, 0.3)',
        opacity: 0.5,
        '& svg': {
          color: 'rgba(255, 255, 255, 0.3)',
        },
      },
    },
  },
};
