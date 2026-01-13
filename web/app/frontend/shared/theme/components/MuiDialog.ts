import { Components, Theme } from '@mui/material';

export const MuiDialog: Components<Theme>['MuiDialog'] = {
  defaultProps: {
    fullWidth: true,
  },
  styleOverrides: {
    paper: {
      background: 'linear-gradient(180deg, #293640 0%, #242C33 100%)',
      boxShadow: '0px 5px 25px 0px rgba(0, 0, 0, 0.50)',
    },
  },
};
