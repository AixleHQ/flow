import { Components, Theme } from '@mui/material';

export const MuiMenu: Components<Theme>['MuiMenu'] = {
  styleOverrides: {
    root: {
      marginTop: '8px',
    },
    paper: {
      borderRadius: '8px',
      border: '1px solid #2E374D',
      background: 'linear-gradient(180deg, #293640 0%, #242C33 100%)',
      boxShadow: '0px 5px 25px 0px rgba(0, 0, 0, 0.50)',
    },
  },
};
