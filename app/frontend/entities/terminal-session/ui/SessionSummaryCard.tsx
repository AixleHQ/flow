import { Box, Chip, Paper, Typography } from '@mui/material';

import type { ITerminalSession } from '../model/types';

const AGENT_LABELS: Record<string, string> = {
  claude_code: 'Claude Code',
  cursor_cli: 'Cursor CLI',
  codex: 'Codex',
  gemini_cli: 'Gemini CLI',
};

const formatTokens = (n: number) => n.toLocaleString('en-US');
const formatCost = (cents: number) => (cents > 0 ? `$${(cents / 100).toFixed(2)}` : null);

export const SessionSummaryCard: React.FC<{ session: ITerminalSession }> = ({ session }) => {
  const toolCount = session.toolIds?.length ?? 0;
  const skillCount = session.skillIds?.length ?? 0;
  const mcpCount = session.mcpServerIds?.length ?? 0;
  const repoCount = session.repositoryIds?.length ?? 0;
  const hasConfig = toolCount + skillCount + mcpCount + repoCount > 0 || session.mode || session.projectName;
  const hasUsage = session.totalTokens > 0 || session.costCents > 0;
  const hasPrompt = !!session.initialPrompt;
  const logsCount = session.sessionLogsCount ?? 0;
  const pendingCount = session.pendingArtifactsCount ?? 0;
  const hasArtifactInfo = logsCount > 0 || pendingCount > 0;

  if (!hasConfig && !hasUsage && !hasArtifactInfo) return null;

  const hasCacheTokens = session.cacheReadTokens > 0 || session.cacheWriteTokens > 0;
  const cost = formatCost(session.costCents);

  return (
    <Paper variant="outlined" sx={{ p: 2, maxWidth: 440, width: '100%', borderRadius: 2 }}>
      {/* Agent + mode + project */}
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.75, mb: 1.5, flexWrap: 'wrap' }}>
        <Chip size="small" label={AGENT_LABELS[session.agentType] ?? session.agentType} />
        {session.mode && (
          <Chip
            size="small"
            label={session.mode === 'interactive' ? 'Interactive' : 'Non-interactive'}
            variant="outlined"
          />
        )}
        {session.projectName && (
          <Typography variant="caption" color="text.secondary" sx={{ ml: 'auto' }}>
            {session.projectName}
          </Typography>
        )}
      </Box>

      {/* Resource counts */}
      {hasConfig && (
        <Box sx={{ display: 'flex', gap: 0.75, flexWrap: 'wrap', mb: hasUsage || hasPrompt ? 1.5 : 0 }}>
          {repoCount > 0 && (
            <Chip
              size="small"
              label={`${repoCount} repo${repoCount > 1 ? 's' : ''}`}
              color="success"
              variant="outlined"
            />
          )}
          {toolCount > 0 && (
            <Chip
              size="small"
              label={`${toolCount} tool${toolCount > 1 ? 's' : ''}`}
              color="warning"
              variant="outlined"
            />
          )}
          {skillCount > 0 && (
            <Chip
              size="small"
              label={`${skillCount} skill${skillCount > 1 ? 's' : ''}`}
              color="secondary"
              variant="outlined"
            />
          )}
          {mcpCount > 0 && <Chip size="small" label={`${mcpCount} MCP`} color="info" variant="outlined" />}
        </Box>
      )}

      {/* Initial prompt */}
      {hasPrompt && (
        <Typography
          variant="caption"
          color="text.secondary"
          sx={{
            display: 'block',
            fontFamily: 'monospace',
            whiteSpace: 'pre-wrap',
            overflow: 'hidden',
            maxHeight: 60,
            textOverflow: 'ellipsis',
            lineHeight: 1.4,
            mb: hasUsage ? 1.5 : 0,
          }}
        >
          {session.initialPrompt!.length > 200 ? `${session.initialPrompt!.slice(0, 200)}…` : session.initialPrompt}
        </Typography>
      )}

      {/* Usage */}
      {hasUsage && (
        <>
          {/* Models + cost */}
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 0.75, flexWrap: 'wrap', mb: 1 }}>
            {session.models?.map((model) => (
              <Chip key={model} size="small" label={model} sx={{ fontSize: '11px', maxWidth: 220 }} />
            ))}
            {cost && (
              <Typography variant="subtitle2" sx={{ ml: 'auto', color: 'success.main', fontFamily: 'monospace' }}>
                {cost}
              </Typography>
            )}
          </Box>

          {/* Token grid */}
          <Box
            sx={{
              display: 'grid',
              gridTemplateColumns: hasCacheTokens ? 'auto 1fr 16px auto 1fr' : 'auto 1fr',
              gap: '2px 12px',
            }}
          >
            <Typography variant="caption" color="text.secondary">
              Input
            </Typography>
            <Typography variant="caption" sx={{ textAlign: 'right', fontFamily: 'monospace' }}>
              {formatTokens(session.inputTokens)}
            </Typography>
            {hasCacheTokens && <Box />}
            {hasCacheTokens && (
              <Typography variant="caption" color="text.secondary">
                Cache read
              </Typography>
            )}
            {hasCacheTokens && (
              <Typography variant="caption" sx={{ textAlign: 'right', fontFamily: 'monospace' }}>
                {formatTokens(session.cacheReadTokens)}
              </Typography>
            )}

            <Typography variant="caption" color="text.secondary">
              Output
            </Typography>
            <Typography variant="caption" sx={{ textAlign: 'right', fontFamily: 'monospace' }}>
              {formatTokens(session.outputTokens)}
            </Typography>
            {hasCacheTokens && <Box />}
            {hasCacheTokens && (
              <Typography variant="caption" color="text.secondary">
                Cache write
              </Typography>
            )}
            {hasCacheTokens && (
              <Typography variant="caption" sx={{ textAlign: 'right', fontFamily: 'monospace' }}>
                {formatTokens(session.cacheWriteTokens)}
              </Typography>
            )}
          </Box>

          {/* Total */}
          <Box
            sx={{
              mt: 0.5,
              pt: 0.5,
              borderTop: 1,
              borderColor: 'divider',
              display: 'flex',
              justifyContent: 'space-between',
            }}
          >
            <Typography variant="caption" color="text.secondary">
              Total
            </Typography>
            <Typography variant="caption" sx={{ fontWeight: 600, fontFamily: 'monospace' }}>
              {formatTokens(session.totalTokens)} tokens
            </Typography>
          </Box>
        </>
      )}

      {/* Artifacts info */}
      {hasArtifactInfo && (
        <Box sx={{ display: 'flex', gap: 0.75, flexWrap: 'wrap', mt: hasUsage ? 1.5 : 0 }}>
          {logsCount > 0 && (
            <Chip size="small" label={`${logsCount} log${logsCount > 1 ? 's' : ''}`} variant="outlined" />
          )}
          {pendingCount > 0 && (
            <Chip
              size="small"
              label={`${pendingCount} output${pendingCount > 1 ? 's' : ''} pending review`}
              color="warning"
              variant="outlined"
            />
          )}
          {session.artifactsReviewed && (
            <Chip size="small" label="Outputs reviewed" color="success" variant="outlined" />
          )}
        </Box>
      )}
    </Paper>
  );
};
