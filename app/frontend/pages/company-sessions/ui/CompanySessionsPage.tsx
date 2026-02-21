import AddIcon from '@mui/icons-material/Add';
import { Box, Button, Typography } from '@mui/material';
import { useNavigate } from '@tanstack/react-router';

import { Routes } from 'shared/routes';
import { SessionHistoryWidget } from 'widgets/session-history';

const CompanySessionsPage = () => {
  const navigate = useNavigate();

  const handleSessionSelect = (id: number) => {
    navigate({ to: Routes.frontend.companySessionPath(String(id)) as string });
  };

  return (
    <Box
      sx={{
        backgroundColor: 'background.default',
        minHeight: 'calc(100vh - 64px)',
        display: 'flex',
        flexDirection: 'column',
      }}
    >
      <Box
        sx={{
          padding: '24px 32px',
          borderBottom: '1px solid',
          borderColor: 'divider',
          backgroundColor: 'background.paper',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
        }}
      >
        <Box>
          <Typography sx={{ fontSize: '28px', fontWeight: 600, color: 'text.primary' }}>Sessions</Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
            Agent session history across the company
          </Typography>
        </Box>
        <Button
          variant="contained"
          startIcon={<AddIcon />}
          onClick={() => navigate({ to: Routes.frontend.companySessionNewPath as string })}
        >
          New Session
        </Button>
      </Box>

      <Box sx={{ px: 4, py: 2, flex: 1 }}>
        <SessionHistoryWidget onSessionSelect={handleSessionSelect} />
      </Box>
    </Box>
  );
};

export default CompanySessionsPage;
