import { Components, Theme } from '@mui/material';

import palette from '../baseTheme/palette';

export const MuiOutlinedInput: Components<Theme>['MuiOutlinedInput'] = {
  styleOverrides: {
    root: {
      backgroundColor: palette.background.surface,
      '& .MuiOutlinedInput-notchedOutline': {
        borderColor: palette.border.defaultAlt,
      },
      '&:hover .MuiOutlinedInput-notchedOutline': {
        borderColor: palette.border.strong,
      },
      '&.Mui-focused .MuiOutlinedInput-notchedOutline': {
        borderColor: palette.primary.main,
        borderWidth: 1,
      },
    },
  },
};
