import { Box, Button, Checkbox, Typography } from '@mui/material';
import { useNavigate } from '@tanstack/react-router';
import { useSnackbar } from 'notistack';
import { useState } from 'react';

import type { AgentType } from 'entities/user';

import { useCompleteOnboardingMutation, useGetOnboardingQuery } from '../api/onboardingApi';

const agentColors: Record<AgentType, string> = {
  codex: '#10a37f',
  cursor_cli: '#7c3aed',
  open_code: '#3b82f6',
  claude_code: '#d97706',
};

const styles = {
  root: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: '100vh',
    padding: '40px 20px',
    background: 'linear-gradient(180deg, #0f0f23 0%, #1a1a2e 50%, #16213e 100%)',
  },
  header: {
    textAlign: 'center',
    marginBottom: '48px',
  },
  title: {
    color: '#FFFFFF',
    fontSize: '42px',
    fontWeight: 700,
    marginBottom: '16px',
    fontFamily: '"JetBrains Mono", monospace',
  },
  subtitle: {
    color: 'rgba(255, 255, 255, 0.7)',
    fontSize: '18px',
    maxWidth: '600px',
    lineHeight: 1.6,
  },
  agentsGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(2, 1fr)',
    gap: '24px',
    maxWidth: '900px',
    width: '100%',
    marginBottom: '48px',
  },
  agentCard: {
    position: 'relative',
    padding: '32px',
    borderRadius: '16px',
    background: 'rgba(255, 255, 255, 0.03)',
    border: '1px solid rgba(255, 255, 255, 0.08)',
    cursor: 'pointer',
    transition: 'all 0.3s ease',
    '&:hover': {
      transform: 'translateY(-4px)',
      border: '1px solid rgba(255, 255, 255, 0.2)',
      boxShadow: '0 20px 40px rgba(0, 0, 0, 0.3)',
    },
  },
  agentCardSelected: {
    border: '2px solid #4785FF',
    background: 'rgba(71, 133, 255, 0.08)',
    '&:hover': {
      border: '2px solid #4785FF',
    },
  },
  agentName: {
    color: '#FFFFFF',
    fontSize: '24px',
    fontWeight: 600,
    marginBottom: '12px',
    fontFamily: '"JetBrains Mono", monospace',
  },
  agentDescription: {
    color: 'rgba(255, 255, 255, 0.6)',
    fontSize: '14px',
    lineHeight: 1.5,
  },
  checkbox: {
    position: 'absolute',
    top: '16px',
    right: '16px',
    '& .MuiSvgIcon-root': {
      fontSize: '28px',
    },
  },
  colorBar: {
    width: '4px',
    height: '40px',
    borderRadius: '2px',
    marginBottom: '20px',
  },
  footer: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    gap: '16px',
  },
  continueButton: {
    minWidth: '280px',
    height: '56px',
    fontSize: '18px',
    fontWeight: 600,
    borderRadius: '12px',
    background: 'linear-gradient(135deg, #4785FF 0%, #7c3aed 100%)',
    textTransform: 'none',
    '&:hover': {
      background: 'linear-gradient(135deg, #5a93ff 0%, #8b5cf6 100%)',
      transform: 'translateY(-2px)',
      boxShadow: '0 10px 30px rgba(71, 133, 255, 0.4)',
    },
    '&:disabled': {
      background: 'rgba(255, 255, 255, 0.1)',
      color: 'rgba(255, 255, 255, 0.3)',
    },
  },
  hint: {
    color: 'rgba(255, 255, 255, 0.4)',
    fontSize: '14px',
  },
} as const;

const OnboardingPage = () => {
  const navigate = useNavigate();
  const { enqueueSnackbar } = useSnackbar();
  const { data, isLoading } = useGetOnboardingQuery();
  const [completeOnboarding, { isLoading: isSubmitting }] = useCompleteOnboardingMutation();
  const [selectedAgents, setSelectedAgents] = useState<AgentType[]>([]);

  const toggleAgent = (agentType: AgentType) => {
    setSelectedAgents((prev) =>
      prev.includes(agentType) ? prev.filter((a) => a !== agentType) : [...prev, agentType],
    );
  };

  const handleContinue = async () => {
    if (selectedAgents.length === 0) {
      enqueueSnackbar('Please select at least one agent', { variant: 'warning' });
      return;
    }

    try {
      await completeOnboarding({ agents: selectedAgents }).unwrap();
      enqueueSnackbar('Onboarding completed! Setting up your agents...', { variant: 'success' });
      navigate({ to: '/setup' });
    } catch {
      enqueueSnackbar('Failed to complete onboarding', { variant: 'error' });
    }
  };

  if (isLoading) {
    return (
      <Box sx={styles.root}>
        <Typography sx={{ color: 'white' }}>Loading...</Typography>
      </Box>
    );
  }

  const agents = data?.agents || [];

  return (
    <Box sx={styles.root}>
      <Box sx={styles.header}>
        <Typography sx={styles.title}>Choose Your AI Agents</Typography>
        <Typography sx={styles.subtitle}>
          Select the AI coding agents you want to use. Each agent will be set up in its own secure Docker container
          with your credentials.
        </Typography>
      </Box>

      <Box sx={styles.agentsGrid}>
        {agents.map((agent) => {
          const isSelected = selectedAgents.includes(agent.type);
          return (
            <Box
              key={agent.type}
              sx={{
                ...styles.agentCard,
                ...(isSelected ? styles.agentCardSelected : {}),
              }}
              onClick={() => toggleAgent(agent.type)}
            >
              <Checkbox
                checked={isSelected}
                sx={styles.checkbox}
                color="primary"
                onClick={(e) => e.stopPropagation()}
                onChange={() => toggleAgent(agent.type)}
              />
              <Box sx={{ ...styles.colorBar, background: agentColors[agent.type] }} />
              <Typography sx={styles.agentName}>{agent.name}</Typography>
              <Typography sx={styles.agentDescription}>{agent.description}</Typography>
            </Box>
          );
        })}
      </Box>

      <Box sx={styles.footer}>
        <Button
          variant="contained"
          sx={styles.continueButton}
          onClick={handleContinue}
          disabled={selectedAgents.length === 0 || isSubmitting}
        >
          {isSubmitting ? 'Setting up...' : `Continue with ${selectedAgents.length} agent${selectedAgents.length !== 1 ? 's' : ''}`}
        </Button>
        <Typography sx={styles.hint}>
          You can change your selection later in settings
        </Typography>
      </Box>
    </Box>
  );
};

export default OnboardingPage;
