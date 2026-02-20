import { ThemeProvider as MuiThemeProvider, CssBaseline } from '@mui/material';
import React from 'react';

import theme from 'shared/theme';

interface ThemeProviderProps {
  children: React.ReactNode;
}

export const ThemeProvider = ({ children }: ThemeProviderProps) => {
  return (
    <MuiThemeProvider theme={theme}>
      <CssBaseline />
      {children}
    </MuiThemeProvider>
  );
};
