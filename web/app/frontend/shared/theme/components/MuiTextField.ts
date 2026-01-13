import { Components, Theme } from '@mui/material';

export const MuiTextField: Components<Theme>['MuiTextField'] = {
  styleOverrides: {
    root: {
      '&.Mui-disabled': {
        opacity: 0.5,
        '& .MuiInputBase-root': {
          '& input': {
            color: 'rgba(255, 255, 255, 0.3) !important',
            WebkitTextFillColor: 'rgba(255, 255, 255, 0.3) !important',
          },
          '& textarea': {
            color: 'rgba(255, 255, 255, 0.3) !important',
            WebkitTextFillColor: 'rgba(255, 255, 255, 0.3) !important',
          },
        },
        '& .MuiInputLabel-root': {
          color: 'rgba(255, 255, 255, 0.3)',
        },
        '& .MuiFormHelperText-root': {
          color: 'rgba(255, 255, 255, 0.3)',
        },
      },
    },
  },
};
