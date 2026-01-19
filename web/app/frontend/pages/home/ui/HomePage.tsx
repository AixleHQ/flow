import { Box, Typography, Button, Paper, CircularProgress } from '@mui/material';
import { useState } from 'react';
import { useNavigate } from '@tanstack/react-router';

// Simple icons using unicode/emoji
const PlayArrowIcon = () => <span style={{ fontSize: '24px' }}>▶</span>;
const TerminalIcon = () => <span style={{ fontSize: '64px' }}>⌨️</span>;

const styles = {
  container: {
    minHeight: '100vh',
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    background: 'linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%)',
    padding: '32px',
  },
  card: {
    padding: '48px',
    maxWidth: '500px',
    width: '100%',
    textAlign: 'center',
    backgroundColor: 'rgba(255, 255, 255, 0.05)',
    backdropFilter: 'blur(10px)',
    border: '1px solid rgba(255, 255, 255, 0.1)',
    borderRadius: '16px',
  },
  icon: {
    fontSize: '64px',
    color: '#4ec9b0',
    marginBottom: '16px',
  },
  title: {
    color: '#ffffff',
    fontWeight: 700,
    marginBottom: '8px',
  },
  subtitle: {
    color: 'rgba(255, 255, 255, 0.7)',
    marginBottom: '32px',
  },
  button: {
    padding: '16px 48px',
    fontSize: '18px',
    fontWeight: 600,
    borderRadius: '12px',
    textTransform: 'none',
    background: 'linear-gradient(135deg, #4ec9b0 0%, #569cd6 100%)',
    '&:hover': {
      background: 'linear-gradient(135deg, #3db89f 0%, #4589c5 100%)',
      transform: 'translateY(-2px)',
      boxShadow: '0 8px 25px rgba(78, 201, 176, 0.3)',
    },
    '&:disabled': {
      background: 'rgba(255, 255, 255, 0.1)',
      color: 'rgba(255, 255, 255, 0.3)',
    },
    transition: 'all 0.2s ease-in-out',
  },
  error: {
    color: '#f44747',
    marginTop: '16px',
  },
} as const;

const HomePage: React.FC = () => {
  const navigate = useNavigate();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleStartSession = async () => {
    setLoading(true);
    setError(null);

    try {
      const response = await fetch('/api/v1/terminal_sessions', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          step_name: 'interactive',
        }),
      });

      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.error || 'Failed to create session');
      }

      // Navigate to session page with ttyd port in state
      navigate({
        to: '/session/$sessionId',
        params: { sessionId: data.id },
        state: { ttydPort: data.ttyd_port },
      });
    } catch (err) {
      setError(err instanceof Error ? err.message : 'An error occurred');
    } finally {
      setLoading(false);
    }
  };

  return (
    <Box sx={styles.container}>
      <Paper elevation={0} sx={styles.card}>
        <TerminalIcon sx={styles.icon} />
        <Typography variant="h3" component="h1" sx={styles.title}>
          Palad
        </Typography>
        <Typography variant="body1" sx={styles.subtitle}>
          Interactive terminal sessions powered by Docker
        </Typography>

        <Button
          variant="contained"
          size="large"
          onClick={handleStartSession}
          disabled={loading}
          startIcon={loading ? <CircularProgress size={24} color="inherit" /> : <PlayArrowIcon />}
          sx={styles.button}
        >
          {loading ? 'Starting...' : 'Start Session'}
        </Button>

        {error && (
          <Typography variant="body2" sx={styles.error}>
            {error}
          </Typography>
        )}
      </Paper>
    </Box>
  );
};

export default HomePage;
