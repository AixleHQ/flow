import { zodResolver } from '@hookform/resolvers/zod';
import { Box, Button, Checkbox, LinearProgress, MenuItem, Select, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useNavigate } from '@tanstack/react-router';
import debounce from 'lodash/debounce';
import { useSnackbar } from 'notistack';
import { useEffect, useMemo, useRef, useState } from 'react';
import { Controller, useForm } from 'react-hook-form';

import type { AgentType, OnboardingState } from 'entities/user';
import {
  AGENT_COLORS,
  AVAILABLE_AGENTS,
  LANGUAGE_OPTIONS,
  getAgentInfo,
  useGetCurrentUserQuery,
  useUpdateCurrentUserMutation,
} from 'entities/user';
import { AgentAuthTerminal } from 'features/agent-auth';
import { Routes } from 'shared/routes';

import { profileSchema, type ProfileFormData } from '../model/profileValidation';

// Constants
const MAX_CONTAINER_WIDTH = '900px';
const LOGO_MAX_WIDTH = '120px';
const LOGO_MAX_HEIGHT = '60px';
const AUTO_SAVE_DELAY = 300; // ms

// Polling constants for credential saving
const CREDENTIAL_POLL_INTERVAL_MS = 500;
const CREDENTIAL_POLL_MAX_ATTEMPTS = 20; // 20 * 500ms = 10 seconds max wait
// Delay before enabling user change tracking after initial data load
// This prevents false-positive auto-saves during component initialization
const USER_CHANGE_TRACKING_DELAY_MS = 100;

type OnboardingStepKey = 'profile' | 'agents' | 'login' | 'complete';

interface IAgentLoginStatus {
  agentType: AgentType;
  status: 'pending' | 'authenticating' | 'authenticated' | 'saving' | 'error';
  sessionUrl?: string;
}

const POSITION_OPTIONS = [
  { value: 'dev', label: 'Developer' },
  { value: 'qa', label: 'QA Engineer' },
  { value: 'pm_po_ba', label: 'Product Manager / BA' },
  { value: 'designer', label: 'Designer' },
  { value: 'cto', label: 'CTO' },
];


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
    maxWidth: MAX_CONTAINER_WIDTH,
    width: '100%',
  },
  welcomeSection: {
    textAlign: 'center',
    marginBottom: '48px',
  },
  companyLogo: {
    maxWidth: LOGO_MAX_WIDTH,
    maxHeight: LOGO_MAX_HEIGHT,
    marginBottom: '24px',
  },
  welcomeTitle: {
    fontSize: '36px',
    fontWeight: 700,
    color: 'text.primary',
    marginBottom: '12px',
  },
  welcomeSubtitle: {
    fontSize: '18px',
    color: 'text.secondary',
    marginBottom: '8px',
  },
  welcomeNote: {
    fontSize: '14px',
    color: 'text.disabled',
    fontStyle: 'italic',
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
  profileForm: {
    maxWidth: '500px',
    margin: '0 auto',
    marginBottom: '48px',
  },
  formField: {
    marginBottom: '24px',
  },
  formLabel: {
    fontSize: '14px',
    fontWeight: 500,
    color: 'text.primary',
    marginBottom: '8px',
    display: 'block',
  },
  requiredAsterisk: {
    color: 'error.main',
    marginLeft: '4px',
  },
  select: {
    width: '100%',
    backgroundColor: 'background.paper',
    '& .MuiSelect-select': {
      padding: '12px 16px',
    },
  },
  validationMessage: {
    fontSize: '12px',
    color: 'warning.main',
    marginTop: '24px',
    padding: '12px',
    backgroundColor: 'rgba(255, 152, 0, 0.1)',
    borderRadius: '8px',
    border: '1px solid',
    borderColor: 'warning.main',
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
    minHeight: '700px',
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
  summaryText: {
    fontSize: '14px',
    color: 'text.primary',
  },
  profileSummary: {
    padding: '16px',
    backgroundColor: 'background.paper',
    borderRadius: '8px',
    border: '1px solid',
    borderColor: 'divider',
    marginBottom: '24px',
    textAlign: 'left',
  },
  profileSummaryRow: {
    display: 'flex',
    justifyContent: 'space-between',
    padding: '8px 0',
    borderBottom: '1px solid',
    borderColor: 'divider',
    '&:last-child': {
      borderBottom: 'none',
    },
  },
  profileSummaryLabel: {
    fontSize: '14px',
    color: 'text.secondary',
  },
  profileSummaryValue: {
    fontSize: '14px',
    color: 'text.primary',
    fontWeight: 500,
  },
} satisfies Record<string, SxProps<Theme>>;

const STEPS: { key: OnboardingStepKey; label: string; state: OnboardingState }[] = [
  { key: 'profile', label: 'Your Profile', state: 'step1' },
  { key: 'agents', label: 'Select Agents', state: 'step2' },
  { key: 'login', label: 'Authenticate', state: 'step3' },
  { key: 'complete', label: 'Complete', state: 'step4' },
];

// Convert OnboardingState to step key for UI
const stateToStepKey = (state: OnboardingState): OnboardingStepKey => {
  const step = STEPS.find((s) => s.state === state);
  return step?.key || 'profile';
};

/**
 * OnboardingPage Component
 *
 * Mandatory 4-step onboarding flow for new users using state machine.
 * State is managed via AASM state machine on backend.
 *
 * **States:** step1, step2, step3, step4, completed
 * **Events:** go_next, go_previous, complete
 */
const OnboardingPage = () => {
  const navigate = useNavigate();
  const { enqueueSnackbar } = useSnackbar();
  const { data: currentUser, isLoading, refetch } = useGetCurrentUserQuery();
  const [updateCurrentUser, { isLoading: isTransitioning }] = useUpdateCurrentUserMutation();

  // Form state with react-hook-form + Zod validation
  const { control, watch, setValue } = useForm<ProfileFormData>({
    resolver: zodResolver(profileSchema),
    mode: 'onChange',
    defaultValues: {
      position: '' as ProfileFormData['position'],
      preferredAgentLanguage: '' as ProfileFormData['preferredAgentLanguage'],
    },
  });

  const position = watch('position');
  const preferredLanguage = watch('preferredAgentLanguage');

  const [selectedAgents, setSelectedAgents] = useState<AgentType[]>([]);
  const [activeLoginAgent, setActiveLoginAgent] = useState<AgentType | null>(null);
  const [loginStatuses, setLoginStatuses] = useState<Record<AgentType, IAgentLoginStatus['status']>>({
    claude_code: 'pending',
    cursor_cli: 'pending',
    codex: 'pending',
    gemini_cli: 'pending',
  });
  // Track if user has attempted to submit (to show validation errors only after attempt)
  const [hasAttemptedSubmit, setHasAttemptedSubmit] = useState(false);

  // Track if this is a user-initiated change (vs initial load)
  const isUserChange = useRef(false);
  // Track last synced user ID to avoid re-syncing same data
  const lastSyncedUserId = useRef<number | null>(null);
  // Track active credential poll interval for cleanup
  const credentialPollIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Debounced auto-save function for profile data
  const debouncedSave = useMemo(
    () =>
      debounce((data: Record<string, unknown>) => {
        updateCurrentUser({ currentUser: data });
      }, AUTO_SAVE_DELAY),
    [updateCurrentUser],
  );

  // Cleanup debounce and polling on unmount
  useEffect(() => {
    return () => {
      debouncedSave.cancel();
      if (credentialPollIntervalRef.current) {
        clearInterval(credentialPollIntervalRef.current);
        credentialPollIntervalRef.current = null;
      }
    };
  }, [debouncedSave]);

  // Initialize/sync from server state when currentUser loads or changes
  useEffect(() => {
    if (!currentUser) return;

    // Only sync once per user load (avoid re-syncing on every render)
    if (lastSyncedUserId.current === currentUser.id) return;
    lastSyncedUserId.current = currentUser.id;

    // Disable user change tracking during sync
    isUserChange.current = false;

    // Pre-fill position
    if (currentUser.position) {
      setValue('position', currentUser.position, { shouldValidate: true });
    }

    // Pre-fill language
    if (currentUser.preferredAgentLanguage) {
      setValue(
        'preferredAgentLanguage',
        currentUser.preferredAgentLanguage as ProfileFormData['preferredAgentLanguage'],
        { shouldValidate: true },
      );
    }

    // Pre-fill selected agents from server
    if (currentUser.selectedAgents && currentUser.selectedAgents.length > 0) {
      setSelectedAgents(currentUser.selectedAgents);
    }

    // Sync login statuses with configuredAgents (from AgentCredentials)
    const configuredAgents = currentUser.configuredAgents || [];
    const newStatuses: Record<AgentType, IAgentLoginStatus['status']> = {
      claude_code: 'pending',
      cursor_cli: 'pending',
      codex: 'pending',
      gemini_cli: 'pending',
    };
    configuredAgents.forEach((agent: AgentType) => {
      newStatuses[agent] = 'authenticated';
    });
    setLoginStatuses(newStatuses);

    // Enable user change tracking after initialization
    setTimeout(() => {
      isUserChange.current = true;
    }, USER_CHANGE_TRACKING_DELAY_MS);
  }, [currentUser, setValue]);

  // Auto-save position on change
  useEffect(() => {
    if (!isUserChange.current || !position) return;
    debouncedSave({ position });
  }, [position, debouncedSave]);

  // Auto-save language on change
  useEffect(() => {
    if (!isUserChange.current || !preferredLanguage) return;
    debouncedSave({ preferredAgentLanguage: preferredLanguage });
  }, [preferredLanguage, debouncedSave]);

  // Auto-save selected agents on change
  useEffect(() => {
    if (!isUserChange.current) return;
    debouncedSave({ selectedAgents });
  }, [selectedAgents, debouncedSave]);

  // Sync loginStatuses when configuredAgents changes (after refetch)
  const configuredAgentsForSync = currentUser?.configuredAgents;
  useEffect(() => {
    if (!configuredAgentsForSync) return;
    setLoginStatuses((prev) => {
      const updated = { ...prev };
      configuredAgentsForSync.forEach((agent: AgentType) => {
        updated[agent] = 'authenticated';
      });
      return updated;
    });
  }, [configuredAgentsForSync]);

  // Get current step from backend state
  const currentStep = currentUser ? stateToStepKey(currentUser.onboardingState) : 'profile';
  const currentStepIndex = STEPS.findIndex((s) => s.key === currentStep);
  const progress = ((currentStepIndex + 1) / STEPS.length) * 100;

  /**
   * Toggles the selection state of an agent and auto-saves.
   */
  const toggleAgent = (agentType: AgentType) => {
    setSelectedAgents((prev) =>
      prev.includes(agentType) ? prev.filter((a) => a !== agentType) : [...prev, agentType],
    );
  };

  /**
   * Handles keyboard interaction for agent selection.
   */
  const handleAgentKeyDown = (event: React.KeyboardEvent, agentType: AgentType) => {
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      toggleAgent(agentType);
    }
  };

  const handleNext = async () => {
    // Mark that user attempted to submit (to show validation errors)
    setHasAttemptedSubmit(true);

    // Validate before proceeding
    if (currentStep === 'profile' && !isProfileComplete) {
      return; // Don't proceed if profile is not complete
    }

    if (currentStep === 'agents' && selectedAgents.length > 0) {
      setActiveLoginAgent(selectedAgents[0]);
    }
    try {
      // Cancel any pending debounced saves and save current state with the transition
      debouncedSave.cancel();
      await updateCurrentUser({
        currentUser: {
          selectedAgents,
          onboardingStateEvent: 'go_next',
        },
      }).unwrap();
      // Reset submit attempt flag when successfully moving to next step
      setHasAttemptedSubmit(false);
    } catch {
      enqueueSnackbar('Failed to proceed to next step', { variant: 'error' });
    }
  };

  const handleBack = async () => {
    try {
      await updateCurrentUser({ currentUser: { onboardingStateEvent: 'go_previous' } }).unwrap();
      // Reset submit attempt flag when going back
      setHasAttemptedSubmit(false);
    } catch {
      enqueueSnackbar('Failed to go back', { variant: 'error' });
    }
  };

  const handleComplete = async () => {
    try {
      await updateCurrentUser({ currentUser: { onboardingStateEvent: 'complete' } }).unwrap();
      enqueueSnackbar('Welcome! Your agents are configured and ready to use.', { variant: 'success' });
      navigate({ to: Routes.frontend.companyProjectsPath });
    } catch {
      enqueueSnackbar(
        'Cannot complete onboarding - please ensure position, language and at least one agent are configured',
        { variant: 'error' },
      );
    }
  };

  // Get authenticated agents from configuredAgents (server state, source of truth)
  const configuredAgents = currentUser?.configuredAgents || [];
  const authenticatedCount = selectedAgents.filter((agent) => configuredAgents.includes(agent)).length;
  const allAgentsAuthenticated = selectedAgents.every((agent) => configuredAgents.includes(agent));

  // Validation flags (check that values are not empty strings)
  const isProfileComplete = Boolean(position) && position.length > 0 && Boolean(preferredLanguage) && preferredLanguage.length > 0;
  const isAgentsSelected = selectedAgents.length >= 1;
  const isAgentsAuthenticated = authenticatedCount >= 1;

  // Can complete onboarding check
  const canComplete = Boolean(position) && Boolean(preferredLanguage) && configuredAgents.length >= 1;

  // Get position label for display
  const getPositionLabel = (value: string) => {
    const option = POSITION_OPTIONS.find((o) => o.value === value);
    return option?.label || value;
  };

  // Get language label for display
  const getLanguageLabel = (value: string) => {
    const option = LANGUAGE_OPTIONS.find((o) => o.value === value);
    return option?.label || value;
  };

  if (isLoading) {
    return (
      <Box sx={styles.root}>
        <Typography sx={{ color: 'white' }}>Loading...</Typography>
      </Box>
    );
  }

  const companyName = currentUser?.company?.name || 'Platform';
  const companyLogo = currentUser?.company?.logoUrl;

  const renderWelcomeSection = () => (
    <Box sx={styles.welcomeSection}>
      {companyLogo && <img src={companyLogo} alt={companyName} style={styles.companyLogo as React.CSSProperties} />}
      <Typography sx={styles.welcomeTitle}>{`Welcome to ${companyName}! 🎉`}</Typography>
      <Typography sx={styles.welcomeSubtitle}>Let&apos;s set up your profile and AI agents to get started</Typography>
      <Typography sx={styles.welcomeNote}>This setup is required to start using the platform</Typography>
    </Box>
  );

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

  const renderProfileStep = () => (
    <>
      <Box sx={styles.header}>
        <Typography sx={styles.title}>Tell Us About Yourself</Typography>
        <Typography sx={styles.subtitle}>
          Help us personalize your experience by sharing a few details about your role and preferences.
        </Typography>
      </Box>

      <Box sx={styles.profileForm}>
        {/* Position Field */}
        <Box sx={styles.formField}>
          <Typography component="label" sx={styles.formLabel}>
            Position in Company
            <span style={styles.requiredAsterisk as React.CSSProperties}>*</span>
          </Typography>
          <Controller
            name="position"
            control={control}
            render={({ field, fieldState }) => (
              <>
                <Select {...field} sx={styles.select} displayEmpty error={!!fieldState.error}>
                  <MenuItem value="" disabled>
                    Please select an option
                  </MenuItem>
                  {POSITION_OPTIONS.map((option) => (
                    <MenuItem key={option.value} value={option.value}>
                      {option.label}
                    </MenuItem>
                  ))}
                </Select>
                {fieldState.error && (
                  <Typography sx={{ fontSize: '12px', color: 'error.main', marginTop: '4px' }}>
                    {fieldState.error.message}
                  </Typography>
                )}
              </>
            )}
          />
        </Box>

        {/* Preferred Language Field */}
        <Box sx={styles.formField}>
          <Typography component="label" sx={styles.formLabel}>
            Preferred Agent Language
            <span style={styles.requiredAsterisk as React.CSSProperties}>*</span>
          </Typography>
          <Controller
            name="preferredAgentLanguage"
            control={control}
            render={({ field, fieldState }) => (
              <>
                <Select {...field} sx={styles.select} displayEmpty error={!!fieldState.error}>
                  <MenuItem value="" disabled>
                    Please select an option
                  </MenuItem>
                  {LANGUAGE_OPTIONS.map((option) => (
                    <MenuItem key={option.value} value={option.value}>
                      {option.label}
                    </MenuItem>
                  ))}
                </Select>
                {fieldState.error && (
                  <Typography sx={{ fontSize: '12px', color: 'error.main', marginTop: '4px' }}>
                    {fieldState.error.message}
                  </Typography>
                )}
              </>
            )}
          />
        </Box>

        {hasAttemptedSubmit && !isProfileComplete && (
          <Typography sx={styles.validationMessage}>⚠️ Please fill in all required fields to continue</Typography>
        )}
      </Box>

      <Box sx={styles.footer}>
        <Box />
        <Button
          variant="contained"
          sx={styles.continueButton}
          onClick={handleNext}
          disabled={isTransitioning || isLoading}
        >
          {isTransitioning ? 'Saving...' : isLoading ? 'Loading...' : 'Continue'}
        </Button>
      </Box>
    </>
  );

  const renderAgentsStep = () => (
    <>
      <Box sx={styles.header}>
        <Typography sx={styles.title}>Select AI Agents to Configure</Typography>
        <Typography sx={styles.subtitle}>
          Select at least one AI coding agent to configure. You&apos;ll authenticate with each service in the next step.
        </Typography>
      </Box>

      <Box sx={styles.grid}>
        {AVAILABLE_AGENTS.map((agent) => {
          const isSelected = selectedAgents.includes(agent.type);
          return (
            <Box
              key={agent.type}
              sx={{
                ...styles.card,
                ...(isSelected ? styles.cardSelected : {}),
              }}
              onClick={() => toggleAgent(agent.type)}
              onKeyDown={(e) => handleAgentKeyDown(e, agent.type)}
              tabIndex={0}
              role="button"
              aria-pressed={isSelected}
              aria-label={`${agent.name}: ${agent.description}`}
            >
              <Checkbox checked={isSelected} sx={styles.checkbox} color="primary" tabIndex={-1} />
              <Box sx={{ ...styles.colorBar, backgroundColor: AGENT_COLORS[agent.type] }} />
              <Typography sx={styles.cardName}>{agent.name}</Typography>
              <Typography sx={styles.cardDescription}>{agent.description}</Typography>
            </Box>
          );
        })}
      </Box>

      {!isAgentsSelected && (
        <Typography sx={styles.validationMessage}>⚠️ Select at least one agent to continue</Typography>
      )}

      <Box sx={styles.footer}>
        <Button sx={styles.backButton} onClick={handleBack} disabled={isTransitioning}>
          Back
        </Button>
        <Button
          variant="contained"
          sx={styles.continueButton}
          onClick={handleNext}
          disabled={!isAgentsSelected || isTransitioning}
        >
          {isTransitioning ? 'Saving...' : 'Continue'}
        </Button>
      </Box>
    </>
  );

  const renderLoginStep = () => (
    <>
      <Box sx={styles.header}>
        <Typography sx={styles.title}>Authenticate Your Agents</Typography>
        <Typography sx={styles.subtitle}>
          Sign in to at least one agent&apos;s service. This creates a secure session for the agent to work on your
          behalf.
        </Typography>
      </Box>

      <Box sx={styles.loginContainer}>
        {/* Agents List */}
        <Box sx={styles.agentsList}>
          {selectedAgents.map((agentType) => {
            const info = getAgentInfo(agentType);
            const isAuthenticated = configuredAgents.includes(agentType);
            const status = loginStatuses[agentType];
            const isActive = activeLoginAgent === agentType;

            return (
              <Box
                key={agentType}
                sx={{
                  ...styles.agentLoginCard,
                  ...(isActive ? styles.agentLoginCardActive : {}),
                  ...(isAuthenticated ? styles.agentLoginCardAuthenticated : {}),
                }}
                onClick={() => setActiveLoginAgent(agentType)}
              >
                <Box sx={styles.agentLoginHeader}>
                  <Box
                    sx={{ ...styles.colorBar, height: '24px', marginBottom: 0 }}
                    style={{ backgroundColor: AGENT_COLORS[agentType] }}
                  />
                  <Typography sx={styles.agentLoginName}>{info.name}</Typography>
                  {isAuthenticated && (
                    <Box sx={{ ...styles.badge, ...styles.badgeAuthenticated, position: 'static' }}>✓</Box>
                  )}
                </Box>
                <Typography sx={styles.agentLoginStatus}>
                  {isAuthenticated && 'Authenticated'}
                  {!isAuthenticated && status === 'pending' && 'Click to authenticate'}
                  {!isAuthenticated && status === 'authenticating' && 'Authenticating...'}
                  {!isAuthenticated && status === 'saving' && 'Saving credentials...'}
                  {!isAuthenticated && status === 'error' && 'Authentication failed'}
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
            <AgentAuthTerminal
              agentType={activeLoginAgent}
              onAuthComplete={() => {
                const justAuthenticatedAgent = activeLoginAgent;
                // Clear active agent to show placeholder while polling
                setActiveLoginAgent(null);
                // Set status to 'saving' to show loading indicator
                setLoginStatuses((prev) => ({ ...prev, [justAuthenticatedAgent]: 'saving' }));
                enqueueSnackbar(`${getAgentInfo(justAuthenticatedAgent).name} - saving credentials...`, {
                  variant: 'info',
                });

                // Clear any existing poll interval before starting new one
                if (credentialPollIntervalRef.current) {
                  clearInterval(credentialPollIntervalRef.current);
                }

                // Poll until credential appears in configuredAgents (Temporal workflow completion)
                let attempts = 0;
                credentialPollIntervalRef.current = setInterval(async () => {
                  attempts++;
                  const result = await refetch();
                  const agents = result.data?.configuredAgents || [];

                  if (agents.includes(justAuthenticatedAgent)) {
                    if (credentialPollIntervalRef.current) {
                      clearInterval(credentialPollIntervalRef.current);
                      credentialPollIntervalRef.current = null;
                    }
                    setLoginStatuses((prev) => ({ ...prev, [justAuthenticatedAgent]: 'authenticated' }));
                    enqueueSnackbar(`${getAgentInfo(justAuthenticatedAgent).name} authenticated!`, {
                      variant: 'success',
                    });
                  } else if (attempts >= CREDENTIAL_POLL_MAX_ATTEMPTS) {
                    if (credentialPollIntervalRef.current) {
                      clearInterval(credentialPollIntervalRef.current);
                      credentialPollIntervalRef.current = null;
                    }
                    setLoginStatuses((prev) => ({ ...prev, [justAuthenticatedAgent]: 'error' }));
                    enqueueSnackbar(`${getAgentInfo(justAuthenticatedAgent).name} - failed to save credentials`, {
                      variant: 'error',
                    });
                  }
                }, CREDENTIAL_POLL_INTERVAL_MS);
              }}
              onCancel={() => {
                setLoginStatuses((prev) => ({ ...prev, [activeLoginAgent]: 'error' }));
                setActiveLoginAgent(null);
              }}
            />
          ) : (
            <Box sx={styles.terminalPlaceholder}>
              <Typography sx={{ fontSize: '48px' }}>🔐</Typography>
              <Typography sx={{ fontSize: '16px' }}>Select an agent to authenticate</Typography>
            </Box>
          )}
        </Box>
      </Box>

      {!isAgentsAuthenticated && (
        <Typography sx={styles.validationMessage}>⚠️ Authenticate at least one agent to continue</Typography>
      )}

      <Box sx={styles.footer}>
        <Button sx={styles.backButton} onClick={handleBack} disabled={isTransitioning}>
          Back
        </Button>
        <Button
          variant="contained"
          sx={styles.continueButton}
          onClick={handleNext}
          disabled={!isAgentsAuthenticated || isTransitioning}
        >
          {isTransitioning
            ? 'Saving...'
            : allAgentsAuthenticated
              ? 'Continue'
              : `Continue (${authenticatedCount}/${selectedAgents.length})`}
        </Button>
      </Box>
    </>
  );

  const renderCompleteStep = () => (
    <Box sx={styles.completeContainer}>
      <Typography sx={styles.completeIcon}>🎉</Typography>
      <Typography sx={styles.completeTitle}>You&apos;re all set!</Typography>
      <Typography sx={styles.completeSubtitle}>
        Review your configuration and click &quot;Get Started&quot; to begin.
      </Typography>

      {/* Profile Summary */}
      <Box sx={{ maxWidth: '400px', margin: '0 auto', marginBottom: '24px' }}>
        <Box sx={styles.profileSummary}>
          <Box sx={styles.profileSummaryRow}>
            <Typography sx={styles.profileSummaryLabel}>Position</Typography>
            <Typography sx={styles.profileSummaryValue}>{position ? getPositionLabel(position) : '—'}</Typography>
          </Box>
          <Box sx={{ ...styles.profileSummaryRow, borderBottom: 'none' }}>
            <Typography sx={styles.profileSummaryLabel}>Language</Typography>
            <Typography sx={styles.profileSummaryValue}>
              {preferredLanguage ? getLanguageLabel(preferredLanguage) : '—'}
            </Typography>
          </Box>
        </Box>

        {/* Agent Summary */}
        {selectedAgents.map((agentType) => {
          const info = getAgentInfo(agentType);
          const isAuthenticated = configuredAgents.includes(agentType);
          return (
            <Box key={agentType} sx={styles.summaryCard}>
              <Box
                sx={{ ...styles.colorBar, height: '24px', marginBottom: 0 }}
                style={{ backgroundColor: AGENT_COLORS[agentType] }}
              />
              <Typography sx={styles.summaryText}>{info.name}</Typography>
              <Typography
                sx={{ marginLeft: 'auto', fontSize: '12px', color: isAuthenticated ? 'success.main' : 'warning.main' }}
              >
                {isAuthenticated ? '✓ Authenticated' : '⚠ Not authenticated'}
              </Typography>
            </Box>
          );
        })}
      </Box>

      {/* Validation warning */}
      {!canComplete && (
        <Typography sx={{ ...styles.validationMessage, maxWidth: '400px', margin: '0 auto 24px' }}>
          ⚠️ Please authenticate at least one agent to complete setup
        </Typography>
      )}

      <Box sx={{ display: 'flex', justifyContent: 'center', gap: '12px' }}>
        <Button sx={styles.backButton} onClick={handleBack} disabled={isTransitioning}>
          Back
        </Button>
        <Button
          variant="contained"
          sx={styles.continueButton}
          onClick={handleComplete}
          disabled={isTransitioning || !canComplete}
        >
          {isTransitioning ? 'Saving...' : 'Get Started'}
        </Button>
      </Box>
    </Box>
  );

  return (
    <Box sx={styles.root}>
      <Box sx={styles.container}>
        {renderWelcomeSection()}
        {renderStepIndicator()}

        {currentStep === 'profile' && renderProfileStep()}
        {currentStep === 'agents' && renderAgentsStep()}
        {currentStep === 'login' && renderLoginStep()}
        {currentStep === 'complete' && renderCompleteStep()}
      </Box>
    </Box>
  );
};

export default OnboardingPage;
