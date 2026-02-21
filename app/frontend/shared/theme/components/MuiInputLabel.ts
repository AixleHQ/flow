import { Components, Theme } from '@mui/material';

export const MuiInputLabel: Components<Theme>['MuiInputLabel'] = {
  styleOverrides: {
    root: {
      color: '#A1A1AA',
      fontSize: '14px',
      '&.Mui-focused': {
        color: '#3B82F6',
      },
    },
  },
};
