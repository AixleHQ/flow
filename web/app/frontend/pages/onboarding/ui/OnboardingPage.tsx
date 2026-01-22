import { Box, Button, Checkbox, CircularProgress, LinearProgress, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useNavigate } from '@tanstack/react-router';
import { useSnackbar } from 'notistack';
import { useState } from 'react';

import type { AgentType } from 'entities/user';

import { useCompleteOnboardingMutation, useGetOnboardingQuery } from '../api/onboardingApi';

type OnboardingStep = 'agents' | 'login' | 'complete';

interface IAgentLoginStatus {
  agentType: AgentType;
  status: 'pending' | 'authenticating' | 'authenticated' | 'error';
  sessionUrl?: string;
}

const agentColors: Record<AgentType, string> = {
  codex: '#10a37f',
  cursor_cli: '#7c3aed',
  gemini_cli: '#3b82f6',
  claude_code: '#d97706',
};

const agentLoginInfo: Record<AgentType, { name: string; description: string; icon: string }> = {
  claude_code: {
    name: 'Claude Code',
    description: 'Authenticate with your Anthropic account to use Claude Code',
    icon: '🤖',
  },
  cursor_cli: {
    name: 'Cursor CLI',
    description: 'Sign in to your Cursor account',
    icon: '⚡',
  },
  codex: {
    name: 'OpenAI Codex',
    description: 'Authenticate with your OpenAI account',
    icon: '🧠',
  },
  gemini_cli: {
    name: 'Gemini CLI',
    description: 'Configure Gemini CLI with your Google API key',
    icon: '🔓',
  },
};

const styles = {
  root: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    minHeight: '100vh',
    padding: '40px 20px',
    background: 'linear-gradient(180deg, #0D0D0D 0%, #1A1A1A 100%)',
  },
  container: {
    maxWidth: '900px',
    width: '100%',
  },
  progressContainer: {
    marginBottom: '48px',
  },
  progressBar: {
    height: '4px',
    borderRadius: '2px',
    backgroundColor: 'rgba(255, 255, 255, 0.1)',
    '& .MuiLinearProgress-bar': {
      backgroundColor: 'primary.main',
    },
  },
  stepsIndicator: {
    display: 'flex',
    justifyContent: 'space-between',
    marginTop: '16px',
  },
  stepDot: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    gap: '8px',
  },
  stepDotCircle: {
    width: '32px',
    height: '32px',
    borderRadius: '50%',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'center',
    fontSize: '14px',
    fontWeight: 600,
    border: '2px solid',
    borderColor: 'divider',
    color: 'text.secondary',
  },
  stepDotCircleActive: {
    borderColor: 'primary.main',
    backgroundColor: 'primary.main',
    color: 'white',
  },
  stepDotCircleCompleted: {
    borderColor: 'success.main',
    backgroundColor: 'success.main',
    color: 'white',
  },
  stepLabel: {
    fontSize: '12px',
    color: 'text.secondary',
  },
  stepLabelActive: {
    color: 'text.primary',
    fontWeight: 500,
  },
  header: {
    textAlign: 'center',
    marginBottom: '48px',
  },
  title: {
    color: 'text.primary',
    fontSize: '32px',
    fontWeight: 700,
    marginBottom: '12px',
  },
  subtitle: {
    color: 'text.secondary',
    fontSize: '16px',
    maxWidth: '500px',
    margin: '0 auto',
    lineHeight: 1.6,
  },
  grid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(2, 1fr)',
    gap: '16px',
    marginBottom: '48px',
  },
  card: {
    position: 'relative',
    padding: '24px',
    borderRadius: '12px',
    backgroundColor: 'background.paper',
    border: '1px solid',
    borderColor: 'divider',
    cursor: 'pointer',
    transition: 'all 0.2s ease',
    '&:hover': {
      borderColor: 'primary.main',
      backgroundColor: 'background.elevated',
    },
  },
  cardSelected: {
    borderColor: 'primary.main',
    backgroundColor: 'rgba(71, 133, 255, 0.08)',
  },
  cardAuthenticated: {
    borderColor: 'success.main',
    backgroundColor: 'rgba(16, 163, 127, 0.08)',
  },
  cardError: {
    borderColor: 'error.main',
    backgroundColor: 'rgba(244, 71, 71, 0.08)',
  },
  cardIcon: {
    fontSize: '32px',
    marginBottom: '12px',
  },
  cardName: {
    fontSize: '18px',
    fontWeight: 600,
    color: 'text.primary',
    marginBottom: '4px',
  },
  cardDescription: {
    fontSize: '13px',
    color: 'text.secondary',
    lineHeight: 1.5,
  },
  checkbox: {
    position: 'absolute',
    top: '12px',
    right: '12px',
  },
  colorBar: {
    width: '4px',
    height: '32px',
    borderRadius: '2px',
    marginBottom: '16px',
  },
  badge: {
    position: 'absolute',
    top: '12px',
    right: '12px',
    padding: '4px 8px',
    borderRadius: '4px',
    fontSize: '11px',
    fontWeight: 600,
    textTransform: 'uppercase',
  },
  badgeAuthenticated: {
    backgroundColor: 'success.main',
    color: 'white',
  },
  badgePending: {
    backgroundColor: 'warning.main',
    color: 'white',
  },
  footer: {
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingTop: '24px',
    borderTop: '1px solid',
    borderColor: 'divider',
  },
  backButton: {
    color: 'text.secondary',
    textTransform: 'none',
  },
  continueButton: {
    minWidth: '160px',
    height: '48px',
    fontSize: '16px',
    fontWeight: 600,
    borderRadius: '8px',
    textTransform: 'none',
  },
  // Login step styles
  loginContainer: {
    display: 'flex',
    gap: '24px',
    marginBottom: '32px',
  },
  agentsList: {
    width: '280px',
    flexShrink: 0,
  },
  agentLoginCard: {
    padding: '16px',
    marginBottom: '12px',
    borderRadius: '8px',
    backgroundColor: 'background.paper',
    border: '1px solid',
    borderColor: 'divider',
    cursor: 'pointer',
    transition: 'all 0.2s ease',
    '&:hover': {
      borderColor: 'primary.main',
    },
  },
  agentLoginCardActive: {
    borderColor: 'primary.main',
    backgroundColor: 'rgba(71, 133, 255, 0.08)',
  },
  agentLoginCardAuthenticated: {
    borderColor: 'success.main',
  },
  agentLoginHeader: {
    display: 'flex',
    alignItems: 'center',
    gap: '12px',
    marginBottom: '4px',
  },
  agentLoginName: {
    fontSize: '14px',
    fontWeight: 600,
    color: 'text.primary',
  },
  agentLoginStatus: {
    fontSize: '12px',
    color: 'text.secondary',
  },
  terminalContainer: {
    flex: 1,
    backgroundColor: '#0D0D0D',
    borderRadius: '12px',
    border: '1px solid',
    borderColor: 'divider',
    overflow: 'hidden',
    minHeight: '500px',
  },
  terminalHeader: {
    padding: '12px 16px',
    backgroundColor: '#1A1A1A',
    borderBottom: '1px solid',
    borderColor: 'divider',
    display: 'flex',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  terminalTitle: {
    fontSize: '14px',
    fontWeight: 500,
    color: 'text.primary',
    display: 'flex',
    alignItems: 'center',
    gap: '8px',
  },
  terminalIframe: {
    width: '100%',
    height: '450px',
    border: 'none',
    backgroundColor: '#0D0D0D',
  },
  terminalPlaceholder: {
    display: 'flex',
    flexDirection: 'column',
    alignItems: 'center',
    justifyContent: 'center',
    height: '450px',
    color: 'text.secondary',
    gap: '16px',
  },
  completeContainer: {
    textAlign: 'center',
    padding: '48px 0',
  },
  completeIcon: {
    fontSize: '64px',
    marginBottom: '24px',
  },
  completeTitle: {
    fontSize: '28px',
    fontWeight: 700,
    color: 'text.primary',
    marginBottom: '12px',
  },
  completeSubtitle: {
    fontSize: '16px',
    color: 'text.secondary',
    marginBottom: '32px',
  },
  summaryCard: {
    padding: '16px',
    backgroundColor: 'background.paper',
    borderRadius: '8px',
    border: '1px solid',
    borderColor: 'divider',
    marginBottom: '12px',
    display: 'flex',
    alignItems: 'center',
    gap: '12px',
  },
  summaryIcon: {
    fontSize: '24px',
  },
  summaryText: {
    fontSize: '14px',
    color: 'text.primary',
  },
} satisfies Record<string, SxProps<Theme>>;

const STEPS: { key: OnboardingStep; label: string }[] = [
  { key: 'agents', label: 'Select Agents' },
  { key: 'login', label: 'Authenticate' },
  { key: 'complete', label: 'Complete' },
];

const OnboardingPage = () => {
  const navigate = useNavigate();
  const { enqueueSnackbar } = useSnackbar();
  const { data, isLoading } = useGetOnboardingQuery();
  const [completeOnboarding, { isLoading: isSubmitting }] = useCompleteOnboardingMutation();

  const [currentStep, setCurrentStep] = useState<OnboardingStep>('agents');
  const [selectedAgents, setSelectedAgents] = useState<AgentType[]>([]);
  const [activeLoginAgent, setActiveLoginAgent] = useState<AgentType | null>(null);
  const [loginStatuses, setLoginStatuses] = useState<Record<AgentType, IAgentLoginStatus['status']>>({
    claude_code: 'pending',
    cursor_cli: 'pending',
    codex: 'pending',
    gemini_cli: 'pending',
  });

  const currentStepIndex = STEPS.findIndex((s) => s.key === currentStep);
  const progress = ((currentStepIndex + 1) / STEPS.length) * 100;

  const toggleAgent = (agentType: AgentType) => {
    setSelectedAgents((prev) =>
      prev.includes(agentType) ? prev.filter((a) => a !== agentType) : [...prev, agentType],
    );
  };

  const handleNext = () => {
    if (currentStep === 'agents' && selectedAgents.length > 0) {
      setActiveLoginAgent(selectedAgents[0]);
    }
    const stepIndex = STEPS.findIndex((s) => s.key === currentStep);
    if (stepIndex < STEPS.length - 1) {
      setCurrentStep(STEPS[stepIndex + 1].key);
    }
  };

  const handleBack = () => {
    const stepIndex = STEPS.findIndex((s) => s.key === currentStep);
    if (stepIndex > 0) {
      setCurrentStep(STEPS[stepIndex - 1].key);
    }
  };

  const handleStartLogin = (agentType: AgentType) => {
    setActiveLoginAgent(agentType);
    setLoginStatuses((prev) => ({ ...prev, [agentType]: 'authenticating' }));
    // In real app, this would start a container session and get ttyd URL
  };

  const handleMarkAuthenticated = (agentType: AgentType) => {
    setLoginStatuses((prev) => ({ ...prev, [agentType]: 'authenticated' }));
    enqueueSnackbar(`${agentLoginInfo[agentType].name} authenticated!`, { variant: 'success' });

    // Move to next agent if available
    const currentIndex = selectedAgents.indexOf(agentType);
    if (currentIndex < selectedAgents.length - 1) {
      setActiveLoginAgent(selectedAgents[currentIndex + 1]);
    }
  };

  const handleComplete = async () => {
    try {
      await completeOnboarding({ agents: selectedAgents }).unwrap();
      enqueueSnackbar('Setup complete! Welcome to Palad.', { variant: 'success' });
      navigate({ to: '/projects' });
    } catch {
      enqueueSnackbar('Failed to complete setup', { variant: 'error' });
    }
  };

  const allAgentsAuthenticated = selectedAgents.every((agent) => loginStatuses[agent] === 'authenticated');
  const authenticatedCount = selectedAgents.filter((agent) => loginStatuses[agent] === 'authenticated').length;

  if (isLoading) {
    return (
      <Box sx={styles.root}>
        <Typography sx={{ color: 'white' }}>Loading...</Typography>
      </Box>
    );
  }

  const agents = data?.agents || [];

  const renderStepIndicator = () => (
    <Box sx={styles.progressContainer}>
      <LinearProgress variant="determinate" value={progress} sx={styles.progressBar} />
      <Box sx={styles.stepsIndicator}>
        {STEPS.map((step, index) => {
          const isActive = step.key === currentStep;
          const isCompleted = index < currentStepIndex;
          return (
            <Box key={step.key} sx={styles.stepDot}>
              <Box
                sx={{
                  ...styles.stepDotCircle,
                  ...(isActive ? styles.stepDotCircleActive : {}),
                  ...(isCompleted ? styles.stepDotCircleCompleted : {}),
                }}
              >
                {isCompleted ? '✓' : index + 1}
              </Box>
              <Typography
                sx={{
                  ...styles.stepLabel,
                  ...(isActive ? styles.stepLabelActive : {}),
                }}
              >
                {step.label}
              </Typography>
            </Box>
          );
        })}
      </Box>
    </Box>
  );

  const renderAgentsStep = () => (
    <>
      <Box sx={styles.header}>
        <Typography sx={styles.title}>Choose Your AI Agents</Typography>
        <Typography sx={styles.subtitle}>
          Select the AI coding agents you want to use. You'll authenticate with each service in the next step.
        </Typography>
      </Box>

      <Box sx={styles.grid}>
        {agents.map((agent) => {
          const isSelected = selectedAgents.includes(agent.type);
          return (
            <Box
              key={agent.type}
              sx={{
                ...styles.card,
                ...(isSelected ? styles.cardSelected : {}),
              }}
              onClick={() => toggleAgent(agent.type)}
            >
              <Checkbox checked={isSelected} sx={styles.checkbox} color="primary" />
              <Box sx={{ ...styles.colorBar, backgroundColor: agentColors[agent.type] }} />
              <Typography sx={styles.cardName}>{agent.name}</Typography>
              <Typography sx={styles.cardDescription}>{agent.description}</Typography>
            </Box>
          );
        })}
      </Box>

      <Box sx={styles.footer}>
        <Box />
        <Button
          variant="contained"
          sx={styles.continueButton}
          onClick={handleNext}
          disabled={selectedAgents.length === 0}
        >
          Continue
        </Button>
      </Box>
    </>
  );

  const renderLoginStep = () => (
    <>
      <Box sx={styles.header}>
        <Typography sx={styles.title}>Authenticate Your Agents</Typography>
        <Typography sx={styles.subtitle}>
          Sign in to each agent's service. This creates a secure session for the agent to work on your behalf.
        </Typography>
      </Box>

      <Box sx={styles.loginContainer}>
        {/* Agents List */}
        <Box sx={styles.agentsList}>
          {selectedAgents.map((agentType) => {
            const info = agentLoginInfo[agentType];
            const status = loginStatuses[agentType];
            const isActive = activeLoginAgent === agentType;
            const isAuthenticated = status === 'authenticated';

            return (
              <Box
                key={agentType}
                sx={{
                  ...styles.agentLoginCard,
                  ...(isActive ? styles.agentLoginCardActive : {}),
                  ...(isAuthenticated ? styles.agentLoginCardAuthenticated : {}),
                }}
                onClick={() => handleStartLogin(agentType)}
              >
                <Box sx={styles.agentLoginHeader}>
                  <Box sx={{ ...styles.colorBar, height: '24px', marginBottom: 0 }} style={{ backgroundColor: agentColors[agentType] }} />
                  <Typography sx={styles.agentLoginName}>{info.name}</Typography>
                  {isAuthenticated && (
                    <Box sx={{ ...styles.badge, ...styles.badgeAuthenticated, position: 'static' }}>✓</Box>
                  )}
                </Box>
                <Typography sx={styles.agentLoginStatus}>
                  {status === 'pending' && 'Click to authenticate'}
                  {status === 'authenticating' && 'Authenticating...'}
                  {status === 'authenticated' && 'Authenticated'}
                  {status === 'error' && 'Authentication failed'}
                </Typography>
              </Box>
            );
          })}

          <Typography sx={{ fontSize: '12px', color: 'text.disabled', marginTop: '16px' }}>
            {authenticatedCount}/{selectedAgents.length} authenticated
          </Typography>
        </Box>

        {/* Terminal/Login Area */}
        <Box sx={styles.terminalContainer}>
          {activeLoginAgent ? (
            <>
              <Box sx={styles.terminalHeader}>
                <Typography sx={styles.terminalTitle}>
                  <span style={{ color: agentColors[activeLoginAgent] }}>●</span>
                  {agentLoginInfo[activeLoginAgent].name} Authentication
                </Typography>
                {loginStatuses[activeLoginAgent] === 'authenticating' && (
                  <Button
                    size="small"
                    variant="contained"
                    color="success"
                    onClick={() => handleMarkAuthenticated(activeLoginAgent)}
                    sx={{ textTransform: 'none', fontSize: '12px' }}
                  >
                    Mark as Authenticated
                  </Button>
                )}
              </Box>

              {loginStatuses[activeLoginAgent] === 'authenticating' ? (
                <Box sx={styles.terminalPlaceholder}>
                  <CircularProgress size={32} />
                  <Typography sx={{ fontSize: '14px' }}>
                    Starting authentication session...
                  </Typography>
                  <Typography sx={{ fontSize: '12px', color: 'text.disabled', maxWidth: '300px', textAlign: 'center' }}>
                    {agentLoginInfo[activeLoginAgent].description}
                  </Typography>
                  {/* In real implementation, this would be an iframe to ttyd */}
                  {/* <iframe src={sessionUrl} style={styles.terminalIframe} /> */}
                </Box>
              ) : loginStatuses[activeLoginAgent] === 'authenticated' ? (
                <Box sx={styles.terminalPlaceholder}>
                  <Typography sx={{ fontSize: '48px' }}>✓</Typography>
                  <Typography sx={{ fontSize: '16px', fontWeight: 600, color: 'success.main' }}>
                    Successfully authenticated!
                  </Typography>
                  <Typography sx={{ fontSize: '12px', color: 'text.disabled' }}>
                    {agentLoginInfo[activeLoginAgent].name} is ready to use
                  </Typography>
                </Box>
              ) : (
                <Box sx={styles.terminalPlaceholder}>
                  <Typography sx={{ fontSize: '14px' }}>
                    Click "Start Authentication" to begin
                  </Typography>
                </Box>
              )}
            </>
          ) : (
            <Box sx={styles.terminalPlaceholder}>
              <Typography sx={{ fontSize: '48px' }}>🔐</Typography>
              <Typography sx={{ fontSize: '16px' }}>
                Select an agent to authenticate
              </Typography>
            </Box>
          )}
        </Box>
      </Box>

      <Box sx={styles.footer}>
        <Button sx={styles.backButton} onClick={handleBack}>
          Back
        </Button>
        <Box sx={{ display: 'flex', gap: '12px' }}>
          {!allAgentsAuthenticated && (
            <Button sx={styles.backButton} onClick={handleNext}>
              Skip for now
            </Button>
          )}
          <Button
            variant="contained"
            sx={styles.continueButton}
            onClick={handleNext}
            disabled={authenticatedCount === 0}
          >
            {allAgentsAuthenticated ? 'Continue' : `Continue (${authenticatedCount}/${selectedAgents.length})`}
          </Button>
        </Box>
      </Box>
    </>
  );

  const renderCompleteStep = () => (
    <Box sx={styles.completeContainer}>
      <Typography sx={styles.completeIcon}>🎉</Typography>
      <Typography sx={styles.completeTitle}>You're all set!</Typography>
      <Typography sx={styles.completeSubtitle}>
        Your AI agents are configured and ready to use.
      </Typography>

      <Box sx={{ maxWidth: '400px', margin: '0 auto', marginBottom: '32px' }}>
        {selectedAgents.map((agentType) => {
          const info = agentLoginInfo[agentType];
          const isAuthenticated = loginStatuses[agentType] === 'authenticated';
          return (
            <Box key={agentType} sx={styles.summaryCard}>
              <Box sx={{ ...styles.colorBar, height: '24px', marginBottom: 0 }} style={{ backgroundColor: agentColors[agentType] }} />
              <Typography sx={styles.summaryText}>{info.name}</Typography>
              <Typography sx={{ marginLeft: 'auto', fontSize: '12px', color: isAuthenticated ? 'success.main' : 'warning.main' }}>
                {isAuthenticated ? '✓ Authenticated' : '⚠ Pending'}
              </Typography>
            </Box>
          );
        })}
      </Box>

      <Box sx={{ display: 'flex', justifyContent: 'center', gap: '12px' }}>
        <Button sx={styles.backButton} onClick={handleBack}>
          Back
        </Button>
        <Button
          variant="contained"
          sx={styles.continueButton}
          onClick={handleComplete}
          disabled={isSubmitting}
        >
          {isSubmitting ? 'Setting up...' : 'Get Started'}
        </Button>
      </Box>
    </Box>
  );

  return (
    <Box sx={styles.root}>
      <Box sx={styles.container}>
        {renderStepIndicator()}

        {currentStep === 'agents' && renderAgentsStep()}
        {currentStep === 'login' && renderLoginStep()}
        {currentStep === 'complete' && renderCompleteStep()}
      </Box>
    </Box>
  );
};

export default OnboardingPage;
