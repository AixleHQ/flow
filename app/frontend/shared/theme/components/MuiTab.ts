import { Components, Theme } from '@mui/material';

export const MuiTab: Components<Theme>['MuiTab'] = {
  styleOverrides: {
    root: {
      textTransform: 'none',
      paddingX: '16px',
      paddingY: '14px',
      color: '#FFFFFFB8',
      '&.Mui-selected': {
        color: '#FFFFFF ',
      },
      '&.Mui-disabled': {
        color: '#808080',
        cursor: 'not-allowed',
        pointerEvents: 'initial',
      },
    },
  },
};
