import { Components, Theme } from '@mui/material';

export const MuiToggleButton: Components<Theme>['MuiToggleButton'] = {
  styleOverrides: {
    root: {
      textTransform: 'none',
      color: 'rgba(255, 255, 255, 0.7)',
      '&.Mui-selected': {
        color: 'rgba(255, 255, 255, 1)',
        backgroundColor: 'rgba(255, 255, 255, 0.1)',
        '&:hover': {
          backgroundColor: 'rgba(255, 255, 255, 0.15)',
        },
      },
      '&:hover': {
        color: 'rgba(255, 255, 255, 0.9)',
        backgroundColor: 'rgba(255, 255, 255, 0.05)',
      },
      '&.Mui-disabled': {
        color: 'rgba(255, 255, 255, 0.3)',
        opacity: 0.5,
        '&.Mui-selected': {
          backgroundColor: 'rgba(255, 255, 255, 0.05)',
          color: 'rgba(255, 255, 255, 0.4)',
        },
      },
    },
  },
};
