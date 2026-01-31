import { Box, CircularProgress } from '@mui/material';
import * as React from 'react';

/**
 * Simple loader component for threpo app
 */
export const Loader: React.FC = () => {
  return (
    <Box
      sx={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        minHeight: '100vh',
      }}
    >
      <CircularProgress />
    </Box>
  );
};

export default Loader;
