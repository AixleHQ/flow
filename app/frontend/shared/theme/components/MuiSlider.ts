export const MuiSlider = {
  styleOverrides: {
    root: {
      height: 4,
      padding: '16px 0',
    },
    thumb: {
      height: 16,
      width: 16,
      backgroundColor: '#fff',
      border: '2px solid #4785FF',
      boxShadow: '0 2px 6px rgba(0,0,0,0.12)',
      '&:focus, &:hover, &.Mui-active': {
        boxShadow: '0 2px 8px rgba(71,133,255,0.24)',
      },
    },
    track: {
      height: 4,
      borderRadius: 2,
      backgroundColor: '#4785FF',
    },
    rail: {
      height: 4,
      borderRadius: 2,
      backgroundColor: '#E3E8EF',
    },
    mark: {
      display: 'none',
    },
  },
};
