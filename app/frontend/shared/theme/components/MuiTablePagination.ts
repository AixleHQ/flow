import { Components, Theme } from '@mui/material';

export const MuiTablePagination: Components<Theme>['MuiTablePagination'] = {
  styleOverrides: {
    root: {
      backgroundColor: '#21222C',
      borderTop: '1px solid rgba(98, 111, 136, 0.56)',
      '& .MuiTablePagination-toolbar': {
        color: 'rgba(255, 255, 255, 0.87)',
      },
      '& .MuiTablePagination-selectLabel, & .MuiTablePagination-displayedRows': {
        color: 'rgba(255, 255, 255, 0.56)',
        fontFamily: 'Poppins',
        fontSize: '14px',
      },
      '& .MuiSelect-icon': {
        color: 'rgba(255, 255, 255, 0.56)',
      },
      '& .MuiIconButton-root': {
        color: 'rgba(255, 255, 255, 0.56)',
      },
      '& .MuiIconButton-root.Mui-disabled': {
        color: 'rgba(255, 255, 255, 0.26)',
      },
    },
  },
};
