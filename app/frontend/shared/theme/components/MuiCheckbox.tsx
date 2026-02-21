import { Components, Theme } from '@mui/material';

import MuiCheckboxCheckedIcon from './MuiCheckboxCheckedIcon';
import MuiCheckboxIndeterminateIcon from './MuiCheckboxIndeterminateIcon';
import MuiCheckboxUncheckedIcon from './MuiCheckboxUncheckedIcon';

export const MuiCheckbox: Components<Theme>['MuiCheckbox'] = {
  defaultProps: {
    icon: <MuiCheckboxUncheckedIcon />,
    checkedIcon: <MuiCheckboxCheckedIcon />,
    indeterminateIcon: <MuiCheckboxIndeterminateIcon />,
  },
  styleOverrides: {
    root: {
      borderRadius: 4,
    },
  },
};
