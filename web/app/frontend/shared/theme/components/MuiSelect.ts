import { Components, Theme } from '@mui/material';

export const MuiSelect: Components<Theme>['MuiSelect'] = {
  styleOverrides: {
    root: {
      '&.Mui-disabled': {
        opacity: 0.5,
        '& .MuiSelect-select': {
          color: 'rgba(255, 255, 255, 0.3)',
          WebkitTextFillColor: 'rgba(255, 255, 255, 0.3)',
        },
        '& .MuiSelect-icon': {
          color: 'rgba(255, 255, 255, 0.3)',
        },
      },
    },
    select: {
      '&.Mui-disabled': {
        color: 'rgba(255, 255, 255, 0.3)',
        WebkitTextFillColor: 'rgba(255, 255, 255, 0.3)',
      },
    },
    icon: {
      color: '#fff',
    },
  },
};
