import { Box, Typography } from '@mui/material';
import { useParams } from '@tanstack/react-router';
import { useCallback, useState } from 'react';

import { Routes } from 'shared/routes';
import { SessionLaunchWidget } from 'widgets/session-launch';

const CompanySessionsPage = () => {
  const params = useParams({ strict: false });
  const sessionId = (params as { sessionId?: string }).sessionId;
  const initialSessionId = sessionId ? Number(sessionId) : undefined;

  // Track active session locally (replaceState doesn't update useParams)
  const [hasActiveSession, setHasActiveSession] = useState(!!initialSessionId);

  // Use replaceState to update URL without triggering route remount
  const handleSessionChange = useCallback((newSessionId: number | null) => {
    setHasActiveSession(!!newSessionId);
    const newUrl = newSessionId
      ? Routes.frontend.companySessionPath(String(newSessionId))
      : Routes.frontend.companySessionsPath;
    window.history.replaceState(null, '', newUrl);
  }, []);

  return (
    <Box
      sx={{
        backgroundColor: 'background.default',
        display: 'flex',
        flexDirection: 'column',
        ...(hasActiveSession
          ? { height: 'calc(100vh - 64px)', overflow: 'hidden' }
          : { minHeight: 'calc(100vh - 64px)' }),
      }}
    >
      {!hasActiveSession && (
        <Box
          sx={{
            padding: '24px 32px',
            borderBottom: '1px solid',
            borderColor: 'divider',
            backgroundColor: 'background.paper',
          }}
        >
          <Typography sx={{ fontSize: '28px', fontWeight: 600, color: 'text.primary' }}>Sessions</Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
            Launch a standalone agent session with company-level resources
          </Typography>
        </Box>
      )}
      <Box sx={{ flex: 1, overflow: 'hidden' }}>
        <SessionLaunchWidget
          initialSessionId={initialSessionId}
          onSessionChange={handleSessionChange}
        />
      </Box>
    </Box>
  );
};

export default CompanySessionsPage;
