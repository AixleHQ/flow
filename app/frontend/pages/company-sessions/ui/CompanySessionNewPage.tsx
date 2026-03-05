import ArrowBackIcon from '@mui/icons-material/ArrowBack';
import { Box, Button, Typography } from '@mui/material';
import { useNavigate, useParams } from '@tanstack/react-router';
import { useCallback, useMemo } from 'react';

import { Routes } from 'shared/routes';
import { SessionLaunchWidget } from 'widgets/session-launch';
import { TerminalSessionWidget } from 'widgets/terminal-session';

const CompanySessionNewPage = () => {
  const navigate = useNavigate();
  const params = useParams({ strict: false }) as { projectId?: string };
  const projectId = useMemo(() => {
    if (params.projectId) return Number(params.projectId);
    try {
      const raw = new URLSearchParams(window.location.search).get('projectId');
      return raw ? Number(raw) : undefined;
    } catch {
      return undefined;
    }
  }, [params.projectId]);

  const handleSessionChange = useCallback(
    (sessionId: number | null) => {
      if (sessionId) {
        const to = projectId
          ? Routes.frontend.companyProjectSessionPath(String(projectId), String(sessionId))
          : Routes.frontend.companySessionPath(String(sessionId));
        navigate({ to: to as string });
      }
    },
    [navigate, projectId],
  );

  const renderTerminal = useCallback(
    ({ sessionId: sid }: { sessionId: number }) => <TerminalSessionWidget sessionId={sid} showEditor showTerminal />,
    [],
  );

  const backTo = projectId
    ? Routes.frontend.companyProjectTabPath(String(projectId), 'sessions')
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
