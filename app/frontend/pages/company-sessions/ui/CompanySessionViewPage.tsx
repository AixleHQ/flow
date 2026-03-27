import ArrowBackIcon from '@mui/icons-material/ArrowBack';
import { Box, Button, Chip, CircularProgress, Typography } from '@mui/material';
import { useNavigate, useParams } from '@tanstack/react-router';
import { useEffect, useState } from 'react';

import { SessionSummaryCard } from 'entities/terminal-session';
import { useTerminalSession } from 'shared/lib';
import { Routes } from 'shared/routes';
import { TerminalSessionWidget } from 'widgets/terminal-session';

const AGENT_LABELS: Record<string, string> = {
  claude_code: 'Claude Code',
  cursor_cli: 'Cursor CLI',
  codex: 'Codex',
  gemini_cli: 'Gemini CLI',
};

const CompanySessionViewPage = () => {
  const params = useParams({ strict: false }) as { sessionId: string; projectId?: string };
  const navigate = useNavigate();
  const id = Number(params.sessionId);
  const routeProjectId = params.projectId;

  const [isStopping, setIsStopping] = useState(false);

  const { session, isLoading, isError, finishSession } = useTerminalSession({
    sessionId: id && !isNaN(id) ? id : null,
  });

  const isTerminal = ['finished', 'failed'].includes(session?.state ?? '');

  // Redirect palad_builder sessions to dedicated page
  useEffect(() => {
    if (session?.metadata?.paladBuilder && routeProjectId) {
      navigate({
        to: Routes.frontend.paladBuilderRunPath(routeProjectId, String(session.id)),
        replace: true,
      });
    }
  }, [session, routeProjectId, navigate]);

  useEffect(() => {
    if (isTerminal && isStopping) setIsStopping(false);
  }, [isTerminal, isStopping]);

  const handleFinish = async () => {
    setIsStopping(true);
    try {
      await finishSession(id);
    } catch {
      setIsStopping(false);
    }
  };

  if (isLoading && !session) {
    return (
      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: 'calc(100vh - 64px)' }}>
        <CircularProgress size={24} />
        <Typography sx={{ ml: 2 }} color="text.secondary">
          Loading session...
        </Typography>
      </Box>
    );
  }

  if (isError && !session) {
    return (
      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: 'calc(100vh - 64px)' }}>
        <Typography color="error">Session not found</Typography>
      </Box>
    );
  }

  const agentLabel = session ? (AGENT_LABELS[session.agentType] ?? session.agentType) : '';

  return (
    <Box sx={{ height: 'calc(100vh - 64px)', display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
      {/* Header */}
      <Box
        sx={{
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          px: 2,
          py: 1,
          borderBottom: '1px solid',
          borderColor: 'divider',
          bgcolor: 'background.paper',
          flexShrink: 0,
        }}
      >
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
          <Button
            size="small"
            startIcon={<ArrowBackIcon />}
            onClick={() => {
              const backTo = routeProjectId
                ? Routes.frontend.companyProjectTabPath(routeProjectId, 'sessions')
                : Routes.frontend.companySessionsPath;
              navigate({ to: backTo as string });
            }}
            sx={{ color: 'text.secondary', minWidth: 'auto' }}
          >
            Back
          </Button>
          <Typography variant="subtitle2">{agentLabel}</Typography>
          {session && (
            <Chip
              size="small"
              label={session.state}
              color={
                session.state === 'ready'
                  ? 'success'
                  : session.state === 'failed'
                    ? 'error'
                    : session.state === 'running'
                      ? 'info'
                      : 'default'
              }
            />
          )}
          <Typography variant="caption" color="text.secondary">
            #{id}
          </Typography>
        </Box>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          {!isTerminal && (
            <Button size="small" variant="outlined" color="error" onClick={handleFinish} disabled={isStopping}>
              {isStopping ? 'Finishing…' : 'Finish'}
            </Button>
          )}
          <Button
            size="small"
            variant="outlined"
            onClick={() => {
              const to = routeProjectId
                ? Routes.frontend.companyProjectSessionNewPath(routeProjectId)
                : Routes.frontend.companySessionNewPath;
              navigate({ to: to as string });
            }}
          >
            New Session
          </Button>
        </Box>
      </Box>

      {/* Terminal or ended state */}
      {isTerminal ? (
        <Box
          sx={{
            flex: 1,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            flexDirection: 'column',
            gap: 2,
          }}
        >
          <Typography variant="h6" color="text.secondary">
            Session {session?.state}
          </Typography>
          {session?.errorMessage && (
            <Typography variant="body2" color="error">
              {session.errorMessage}
            </Typography>
          )}
          {session && <SessionSummaryCard session={session} />}
          {session && !session.artifactsReviewed && (session.pendingArtifactsCount ?? 0) > 0 && (
            <Button
              variant="contained"
              color="warning"
              onClick={() => {
                const pid = routeProjectId || (session.projectId ? String(session.projectId) : null);
                const to = pid
                  ? Routes.frontend.companyProjectSessionArtifactsPath(pid, params.sessionId)
                  : Routes.frontend.companySessionArtifactsPath(params.sessionId);
                navigate({ to });
              }}
            >
              Review Outputs ({session.pendingArtifactsCount} files)
            </Button>
          )}
          <Box sx={{ display: 'flex', gap: 1 }}>
            <Button
              variant="outlined"
              onClick={() => {
                const pid = routeProjectId || (session?.projectId ? String(session.projectId) : null);
                const path = pid
                  ? Routes.frontend.companyProjectTabPath(pid, 'sessions')
                  : Routes.frontend.companySessionsPath;
                navigate({ to: path as string });
              }}
            >
              All Sessions
            </Button>
            <Button
              variant="contained"
              onClick={() => {
                const pid = routeProjectId || (session?.projectId ? String(session.projectId) : null);
                const to = pid
                  ? Routes.frontend.companyProjectSessionNewPath(pid)
                  : Routes.frontend.companySessionNewPath;
                navigate({ to: to as string });
              }}
            >
              New Session
            </Button>
          </Box>
        </Box>
      ) : (
        <Box sx={{ flex: 1, overflow: 'hidden' }}>
          <TerminalSessionWidget sessionId={id} showEditor showTerminal />
        </Box>
      )}
    </Box>
  );
};

export default CompanySessionViewPage;
