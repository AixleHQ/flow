import { Box, Typography } from '@mui/material';
import React from 'react';

const HomePage: React.FC = () => {
  return (
    <Box sx={{ padding: 4, textAlign: 'center' }}>
      <Typography variant="h2" component="h1" gutterBottom>
        Welcome to Palad
      </Typography>
      <Typography variant="body1" color="text.secondary">
        Your application is ready to go!
      </Typography>
    </Box>
  );
};

export default HomePage;
