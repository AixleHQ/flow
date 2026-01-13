import { SxProps } from '@mui/material';

declare global {
  export type SxProperties = SxProps<Theme>;

  export type SxStyles<T = string> = Record<T, SxProperties>;
}
