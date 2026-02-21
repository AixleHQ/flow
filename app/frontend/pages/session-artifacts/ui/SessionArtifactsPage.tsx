import ArrowBackIcon from '@mui/icons-material/ArrowBack';
import CheckBoxIcon from '@mui/icons-material/CheckBox';
import CheckBoxOutlineBlankIcon from '@mui/icons-material/CheckBoxOutlineBlank';
import DescriptionIcon from '@mui/icons-material/Description';
import DownloadIcon from '@mui/icons-material/Download';
import {
  Alert,
  Box,
  Button,
  Checkbox,
  CircularProgress,
  IconButton,
  Link,
  Paper,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Typography,
} from '@mui/material';
import { useNavigate, useParams } from '@tanstack/react-router';
import { useSnackbar } from 'notistack';
import { useCallback, useState } from 'react';

import type { ISessionArtifact } from 'entities/terminal-session';
import { useGetSessionArtifactsQuery, useGetTerminalSessionQuery, useReviewSessionArtifactsMutation } from 'shared/api';
import { Routes } from 'shared/routes';

const formatFileSize = (bytes: number | null) => {
  if (!bytes) return '\u2014';
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
};

const SessionArtifactsPage = () => {
  const params = useParams({ strict: false }) as { sessionId: string; projectId?: string };
  const navigate = useNavigate();
  const { enqueueSnackbar } = useSnackbar();

  const sessionId = Number(params.sessionId);
  const projectId = params.projectId;

  const { data: sessionData, isLoading: sessionLoading } = useGetTerminalSessionQuery(sessionId);
  const { data: artifacts = [], isLoading: artifactsLoading } = useGetSessionArtifactsQuery(sessionId);
  const [reviewArtifacts, { isLoading: isReviewing }] = useReviewSessionArtifactsMutation();

  const session = sessionData?.data;

  const [selected, setSelected] = useState<Set<number>>(new Set());

  const isLoading = sessionLoading || artifactsLoading;

  const handleToggle = useCallback((id: number) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }, []);

  const handleToggleAll = useCallback(() => {
    setSelected((prev) =>
      prev.size === artifacts.length ? new Set() : new Set(artifacts.map((a: ISessionArtifact) => a.id)),
    );
  }, [artifacts]);

  const backPath = projectId
    ? Routes.frontend.companyProjectSessionPath(projectId, params.sessionId)
    : Routes.frontend.companySessionPath(params.sessionId);

  const handleReview = useCallback(
    async (dismissAll: boolean) => {
      const decisions: Record<string, 'save' | 'dismiss'> = {};
      for (const a of artifacts) {
        decisions[String(a.id)] = dismissAll ? 'dismiss' : selected.has(a.id) ? 'save' : 'dismiss';
      }
      try {
        await reviewArtifacts({
          sessionId,
          decisions,
        }).unwrap();
        enqueueSnackbar(dismissAll ? 'All outputs dismissed' : 'Outputs reviewed successfully', { variant: 'success' });
        navigate({ to: backPath });
      } catch {
        enqueueSnackbar('Failed to review outputs', { variant: 'error' });
      }
    },
    [artifacts, selected, sessionId, reviewArtifacts, enqueueSnackbar, navigate, backPath],
  );

  if (isLoading) {
    return (
      <Box display="flex" justifyContent="center" alignItems="center" minHeight={300}>
        <CircularProgress />
      </Box>
    );
  }

  const isReviewed = session?.artifactsReviewed;

  return (
    <Box p={3} maxWidth={900} mx="auto">
      <Box display="flex" alignItems="center" gap={1} mb={3}>
        <IconButton onClick={() => navigate({ to: backPath })} size="small">
          <ArrowBackIcon />
        </IconButton>
        <Typography variant="h5">Review Session Outputs</Typography>
      </Box>

      {isReviewed && (
        <Alert severity="info" sx={{ mb: 3 }}>
          Outputs for this session have already been reviewed.{' '}
          <Link component="button" onClick={() => navigate({ to: backPath })} sx={{ cursor: 'pointer' }}>
            Back to session
          </Link>
        </Alert>
      )}

      {!isReviewed && artifacts.length === 0 && <Alert severity="info">No outputs collected from this session.</Alert>}

      {artifacts.length > 0 && !isReviewed && (
        <>
          <TableContainer component={Paper} variant="outlined" sx={{ mb: 3 }}>
            <Table size="small">
              <TableHead>
                <TableRow>
                  <TableCell padding="checkbox">
                    <Checkbox
                      checked={selected.size === artifacts.length && artifacts.length > 0}
                      indeterminate={selected.size > 0 && selected.size < artifacts.length}
                      onChange={handleToggleAll}
                      icon={<CheckBoxOutlineBlankIcon />}
                      checkedIcon={<CheckBoxIcon />}
                    />
                  </TableCell>
                  <TableCell>File</TableCell>
                  <TableCell align="right">Size</TableCell>
                  <TableCell align="right">Type</TableCell>
                  <TableCell align="center">Download</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {artifacts.map((artifact: ISessionArtifact) => (
                  <TableRow key={artifact.id} hover>
                    <TableCell padding="checkbox">
                      <Checkbox checked={selected.has(artifact.id)} onChange={() => handleToggle(artifact.id)} />
                    </TableCell>
                    <TableCell>
                      <Box display="flex" alignItems="center" gap={1}>
                        <DescriptionIcon fontSize="small" color="action" />
                        {artifact.name}
                      </Box>
                    </TableCell>
                    <TableCell align="right">{formatFileSize(artifact.fileSize)}</TableCell>
                    <TableCell align="right" sx={{ color: 'text.secondary', fontSize: '0.85rem' }}>
                      {artifact.contentType ?? '\u2014'}
                    </TableCell>
                    <TableCell align="center">
                      {artifact.downloadUrl && (
                        <IconButton size="small" href={artifact.downloadUrl} target="_blank">
                          <DownloadIcon fontSize="small" />
                        </IconButton>
                      )}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </TableContainer>

          <Box display="flex" gap={2}>
            <Button
              variant="contained"
              disabled={selected.size === 0 || isReviewing}
              onClick={() => handleReview(false)}
            >
              {isReviewing ? <CircularProgress size={20} sx={{ mr: 1 }} /> : null}
              Save selected ({selected.size})
            </Button>
            <Button variant="outlined" color="warning" disabled={isReviewing} onClick={() => handleReview(true)}>
              Dismiss all
            </Button>
          </Box>
        </>
      )}
    </Box>
  );
};

export default SessionArtifactsPage;
