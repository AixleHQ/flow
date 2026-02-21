import { createTheme } from '@mui/material/styles';

import palette from './palette';
import typography from './typography';

const baseTheme = createTheme({
  palette,
  typography,
});

export default baseTheme;
