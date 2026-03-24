import { keyframes } from '@mui/system';

export const workflowPulse = keyframes`
  0%, 100% { opacity: 1; }
  50% { opacity: 0.4; }
`;

export const WORKFLOW_ACTIVE_STATES = new Set(['pending', 'running', 'paused']);

export function workflowStatusColor(state: string): string {
  if (WORKFLOW_ACTIVE_STATES.has(state)) return '#1976d2';
  if (state === 'failed') return '#d32f2f';
  if (state === 'cancelled') return '#9e9e9e';
  return '#2e7d32';
}
