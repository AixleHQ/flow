import { Components, Theme } from '@mui/material';

import palette from '../baseTheme/palette';

export const MuiButton: Components<Theme>['MuiButton'] = {
  variants: [
    {
      props: { variant: 'flat' },
      style: {
        background: '#000',
        border: 'none',
        color: 'rgba(255, 255, 255, 0.72)',
        '& svg': {
          color: palette.primary.main,
        },
      },
    },
  ],
  styleOverrides: {
    root: {
      textTransform: 'none',
    },
    outlined: {
      border: '1px solid #4a5266',
      background: 'rgba(255, 255, 255, 0.02)',
      color: '#fff',
      position: 'relative',
      overflow: 'hidden',

      '&.Mui-disabled': {
        color: 'rgba(255, 255, 255, 0.72)',
        opacity: 0.4,
        border: '1px solid rgba(98, 111, 136, 0.56)',
      },

      '&.button-active': {
        border: '1px solid #5F78FF',
        backgroundColor: 'rgba(255, 255, 255, 0.02)',
        '&::after': {
          content: '""',
          position: 'absolute',
          bottom: 0,
          left: 0,
          width: '100%',
          height: 12,
          overflow: 'hidden',
          backgroundImage: 'url("/button-active.svg")',
          backgroundSize: '100% 12px',
          backgroundRepeat: 'no-repeat',
          backgroundPosition: 'center bottom',
          filter: 'blur(12px)',
        },
      },
    },
    contained: {
      color: '#fff',
      border: '1px solid',
      borderColor: 'rgba(95, 120, 255, 0.24)',
      boxShadow: '0px 4px 12px 0px #121619',
      background: 'linear-gradient(180deg, rgba(50,52,75,1) 0%, rgba(33,34,44,1) 100%)',
      '&:hover': {
        boxShadow: '0px 4px 12px 0px #0037A352',
      },
      '&.Mui-disabled': {
        color: 'rgba(255, 255, 255, 0.72)',
        opacity: 0.4,
        border: '1px solid rgba(98, 111, 136, 0.56)',
        '& svg': {
          color: '#626F88',
        },
      },
    },
    sizeMedium: {
      padding: '7px 22px',
      fontSize: '16px',
      fontWeight: 500,
      lineHeight: '24px',
      letterSpacing: '0.01em',
      borderRadius: '8px',
    },
    sizeLarge: {
      paddingLeft: 24,
      paddingRight: 24,
      height: 56,
      fontSize: '16px',
      fontWeight: 500,
      lineHeight: '24px',
      letterSpacing: '0.01em',
      borderRadius: '8px',
    },
  },
};
