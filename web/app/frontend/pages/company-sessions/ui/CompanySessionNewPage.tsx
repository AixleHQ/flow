import ArrowBackIcon from '@mui/icons-material/ArrowBack';
import { Box, Button, Typography } from '@mui/material';
import { useNavigate } from '@tanstack/react-router';
import { useCallback, useMemo } from 'react';

import { Routes } from 'shared/routes';
import { SessionLaunchWidget } from 'widgets/session-launch';
import { TerminalSessionWidget } from 'widgets/terminal-session';

function useProjectIdFromUrl(): number | undefined {
  try {
    const params = new URLSearchParams(window.location.search);
    const raw = params.get('projectId');
    return raw ? Number(raw) : undefined;
  } catch {
    return undefined;
  }
}

const CompanySessionNewPage = () => {
  const navigate = useNavigate();
  const projectId = useMemo(() => useProjectIdFromUrl(), []);

  const handleSessionChange = useCallback(
    (sessionId: number | null) => {
      if (sessionId) {
        navigate({ to: Routes.frontend.companySessionPath(String(sessionId)) as string });
      }
    },
    [navigate],
  );

  const renderTerminal = useCallback(
    ({
      sessionId: sid,
      session,
    }: {
      sessionId: number;
      session: import('entities/terminal-session').ITerminalSession | null;
    }) => <TerminalSessionWidget sessionId={sid} session={session} showFileTree showFileViewer showTerminal />,
    [],
  );

  const backTo = projectId
    ? Routes.frontend.companyProjectPath(String(projectId))
    : Routes.frontend.companySessionsPath;

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
          gap: 2,
        }}
      >
        <Button
          size="small"
          startIcon={<ArrowBackIcon />}
          onClick={() => navigate({ to: backTo as string })}
          sx={{ color: 'text.secondary' }}
        >
          Back
        </Button>
        <Typography sx={{ fontSize: '22px', fontWeight: 600, color: 'text.primary' }}>New Session</Typography>
      </Box>

      <Box sx={{ flex: 1, px: 4, py: 2 }}>
        <SessionLaunchWidget
          projectId={projectId}
          onSessionChange={handleSessionChange}
          renderTerminal={renderTerminal}
        />
      </Box>
    </Box>
  );
};

export default CompanySessionNewPage;
