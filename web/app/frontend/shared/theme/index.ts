import { createTheme } from '@mui/material/styles';

import baseTheme from './baseTheme';
import components from './components';

const theme = createTheme(baseTheme, {
  components,
});

export default theme;
