import ArrowBackIcon from '@mui/icons-material/ArrowBack';
import { Box, Button, Chip, CircularProgress, Typography } from '@mui/material';
import { useNavigate, useParams } from '@tanstack/react-router';
import { useCallback, useEffect, useState } from 'react';

import type { ITerminalSession } from 'entities/terminal-session';
import { useFinishSessionMutation, useGetTerminalSessionQuery } from 'shared/api';
import { useTerminalSessionChannel } from 'shared/lib';
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

  const [session, setSession] = useState<ITerminalSession | null>(null);
  const [isStopping, setIsStopping] = useState(false);

  const { data, isLoading, isError } = useGetTerminalSessionQuery(id, {
    skip: !id || isNaN(id) || !!session,
  });
  const [finishSession] = useFinishSessionMutation();

  // Sync fetched data into local state (via effect, not during render)
  useEffect(() => {
    if (data?.data && !session) {
      setSession(data.data);
    }
  }, [data, session]);

  // ActionCable subscription
  useTerminalSessionChannel({
    sessionId: id,
    onUpdate: useCallback((updated: ITerminalSession) => setSession(updated), []),
  });

  const isTerminal = ['stopped', 'collected', 'failed', 'cancelled'].includes(session?.state ?? '');

  useEffect(() => {
    if (isTerminal && isStopping) setIsStopping(false);
  }, [isTerminal, isStopping]);

  const handleFinish = async () => {
    setIsStopping(true);
    try {
      await finishSession({ sessionId: id }).unwrap();
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
              color={session.state === 'running' ? 'success' : session.state === 'failed' ? 'error' : 'default'}
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
          <TerminalSessionWidget sessionId={id} session={session} showFileTree showFileViewer showTerminal />
        </Box>
      )}
    </Box>
  );
};

export default CompanySessionViewPage;
