import { zodResolver } from '@hookform/resolvers/zod';
import { Box, Button, Checkbox, LinearProgress, MenuItem, Select, Typography } from '@mui/material';
import type { SxProps, Theme } from '@mui/material/styles';
import { useNavigate } from '@tanstack/react-router';
import { useSnackbar } from 'notistack';
import { useEffect, useRef, useState } from 'react';
import { Controller, useForm } from 'react-hook-form';

import type { AgentType } from 'entities/user';
import { useGetCurrentUserQuery, useUpdateCurrentUserMutation } from 'entities/user/api/currentUserApi';
import { AgentAuthTerminal } from 'features/agent-auth/ui';

import { profileSchema, type ProfileFormData } from '../model/profileValidation';

// Constants
const MAX_CONTAINER_WIDTH = '900px';
const LOGO_MAX_WIDTH = '120px';
const LOGO_MAX_HEIGHT = '60px';

type OnboardingStep = 'profile' | 'agents' | 'login' | 'complete';

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

// Available agents list with detailed descriptions (single source of truth)
const AVAILABLE_AGENTS: Array<{ type: AgentType; name: string; description: string }> = [
  {
    type: 'claude_code',
    name: 'Claude Code',
    description: "Anthropic's AI coding assistant with deep reasoning capabilities",
  },
  {
    type: 'cursor_cli',
    name: 'Cursor CLI',
    description: 'AI-powered code editor with context-aware suggestions',
  },
  {
    type: 'codex',
    name: 'OpenAI Codex',
    description: "OpenAI's code generation model optimized for multiple languages",
  },
  {
    type: 'gemini_cli',
    name: 'Gemini CLI',
    description: "Google's multimodal AI for code and documentation tasks",
  },
];

// Helper to get agent info by type
const getAgentInfo = (type: AgentType) => AVAILABLE_AGENTS.find((a) => a.type === type)!;

const POSITION_OPTIONS = [
  { value: 'dev', label: 'Developer' },
  { value: 'qa', label: 'QA Engineer' },
  { value: 'pm_po_ba', label: 'Product Manager / BA' },
  { value: 'designer', label: 'Designer' },
  { value: 'cto', label: 'CTO' },
];

const LANGUAGE_OPTIONS = [
  { value: 'en', label: 'English' },
  { value: 'ru', label: 'Russian' },
  { value: 'es', label: 'Spanish' },
  { value: 'de', label: 'German' },
  { value: 'fr', label: 'French' },
  { value: 'ja', label: 'Japanese' },
  { value: 'zh', label: 'Chinese' },
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
  { key: 'profile', label: 'Your Profile' },
  { key: 'agents', label: 'Select Agents' },
  { key: 'login', label: 'Authenticate' },
  { key: 'complete', label: 'Complete' },
];

/**
 * OnboardingPage Component
 *
 * Mandatory 4-step onboarding flow for new users. Users cannot skip onboarding and must complete
 * all steps before accessing the platform.
 *
 * **Flow:**
 * 1. **Step 1 - Your Profile:** User selects position and preferred agent language (required fields)
 * 2. **Step 2 - Select Agents:** User selects at least 1 AI agent to configure
 * 3. **Step 3 - Authenticate:** User authenticates at least 1 selected agent
 * 4. **Step 4 - Complete:** User reviews and confirms setup, triggering API call
 *
 * **Required Fields:**
 * - Position: dev, qa, pm_po_ba, designer, cto
 * - Preferred Agent Language: en, ru, es, de, fr, ja, zh
 * - Configured Agents: At least 1 authenticated agent
 *
 * **Edit Mode:**
 * Users who have completed onboarding can return to `/onboarding` to edit their profile and agents.
 * Edit mode pre-fills existing values and changes button text from "Get Started" to "Save Changes".
 *
 * **Validation:**
 * - Step 1: Both fields required (validated with Zod)
 * - Step 2: At least 1 agent must be selected
 * - Step 3: At least 1 agent must be authenticated
 * - No progress persistence - must complete in one session
 *
 * @returns {JSX.Element} Onboarding page with 4-step flow
 */
const OnboardingPage = () => {
  const navigate = useNavigate();
  const { enqueueSnackbar } = useSnackbar();
  const { data: currentUser, isLoading } = useGetCurrentUserQuery();
  const [updateCurrentUser, { isLoading: isSubmitting }] = useUpdateCurrentUserMutation();

  // Form state with react-hook-form + Zod validation
  const {
    control,
    watch,
    setValue,
    formState: { isValid },
  } = useForm<ProfileFormData>({
    resolver: zodResolver(profileSchema),
    mode: 'onChange',
    defaultValues: {
      position: '' as ProfileFormData['position'],
      preferredAgentLanguage: '' as ProfileFormData['preferredAgentLanguage'],
    },
  });

  const position = watch('position');
  const preferredLanguage = watch('preferredAgentLanguage');

  const [currentStep, setCurrentStep] = useState<OnboardingStep>('profile');
  const [selectedAgents, setSelectedAgents] = useState<AgentType[]>([]);
  const [activeLoginAgent, setActiveLoginAgent] = useState<AgentType | null>(null);
  const [loginStatuses, setLoginStatuses] = useState<Record<AgentType, IAgentLoginStatus['status']>>({
    claude_code: 'pending',
    cursor_cli: 'pending',
    codex: 'pending',
    gemini_cli: 'pending',
  });
  const [isEditMode, setIsEditMode] = useState(false);

  // Track if onboarding guard has been initialized (prevent duplicate redirects in React Strict Mode)
  const onboardingGuardInitialized = useRef(false);

  // Initialize edit mode and pre-fill data
  useEffect(() => {
    if (!currentUser || onboardingGuardInitialized.current) return;

    onboardingGuardInitialized.current = true;

    // If onboarding already completed, enable edit mode and pre-fill
    if (currentUser.onboardingCompletedAt) {
      setIsEditMode(true);
      if (currentUser.position) {
        setValue('position', currentUser.position);
      }
      if (currentUser.preferredAgentLanguage) {
        setValue(
          'preferredAgentLanguage',
          currentUser.preferredAgentLanguage as ProfileFormData['preferredAgentLanguage'],
        );
      }
      setSelectedAgents(currentUser.configuredAgents || []);
      // Mark all configured agents as authenticated in edit mode
      if (currentUser.configuredAgents) {
        const newStatuses: Record<AgentType, IAgentLoginStatus['status']> = {
          claude_code: 'pending',
          cursor_cli: 'pending',
          codex: 'pending',
          gemini_cli: 'pending',
        };
        currentUser.configuredAgents.forEach((agent: AgentType) => {
          newStatuses[agent] = 'authenticated';
        });
        setLoginStatuses(newStatuses);
      }
    }
  }, [currentUser, setValue]);

  const currentStepIndex = STEPS.findIndex((s) => s.key === currentStep);
  const progress = ((currentStepIndex + 1) / STEPS.length) * 100;

  /**
   * Toggles the selection state of an agent.
   * Adds the agent to selectedAgents if not present, removes if already selected.
   * Used in Step 2 (Select Agents) to allow users to choose which AI agents to configure.
   * @param agentType - The type of agent to toggle (claude_code, cursor_cli, codex, gemini_cli)
   */
  const toggleAgent = (agentType: AgentType) => {
    setSelectedAgents((prev) =>
      prev.includes(agentType) ? prev.filter((a) => a !== agentType) : [...prev, agentType],
    );
  };

  /**
   * Handles keyboard interaction for agent selection.
   * Allows selecting agents with Enter or Space keys for accessibility.
   * @param event - Keyboard event
   * @param agentType - The type of agent to toggle
   */
  const handleAgentKeyDown = (event: React.KeyboardEvent, agentType: AgentType) => {
    if (event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      toggleAgent(agentType);
    }
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

  const handleComplete = async () => {
    try {
      // Only send agents that were authenticated
      const authenticatedAgents = selectedAgents.filter((agent) => loginStatuses[agent] === 'authenticated');

      await updateCurrentUser({
        currentUser: {
          position: position as 'dev' | 'qa' | 'pm_po_ba' | 'designer' | 'cto',
          preferredAgentLanguage: preferredLanguage,
          configuredAgents: authenticatedAgents,
        },
      }).unwrap();
      enqueueSnackbar('Setup complete! Welcome to Palad.', { variant: 'success' });
      navigate({ to: '/projects' });
    } catch {
      enqueueSnackbar('Failed to complete setup', { variant: 'error' });
    }
  };

  const allAgentsAuthenticated = selectedAgents.every((agent) => loginStatuses[agent] === 'authenticated');
  const authenticatedCount = selectedAgents.filter((agent) => loginStatuses[agent] === 'authenticated').length;

  // Validation flags
  const isProfileComplete = isValid; // Uses Zod validation
  /**
   * Validates that at least one agent is selected.
   * Required to proceed from Step 2 (Select Agents) to Step 3 (Authenticate).
   */
  const isAgentsSelected = selectedAgents.length >= 1;
  /**
   * Validates that at least one agent has been authenticated.
   * Required to proceed from Step 3 (Authenticate) to Step 4 (Complete).
   */
  const isAgentsAuthenticated = authenticatedCount >= 1;

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
      <Typography sx={styles.welcomeTitle}>
        {isEditMode ? `Manage Your Profile & Agents` : `Welcome to ${companyName}! 🎉`}
      </Typography>
      <Typography sx={styles.welcomeSubtitle}>
        {isEditMode
          ? 'Update your profile information and agent configurations'
          : "Let's set up your profile and AI agents to get started"}
      </Typography>
      {!isEditMode && (
        <Typography sx={styles.welcomeNote}>This setup is required to start using the platform</Typography>
      )}
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
                    Select your position
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
                    Select your preferred language
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

        {!isProfileComplete && (
          <Typography sx={styles.validationMessage}>⚠️ Please fill in all required fields to continue</Typography>
        )}
      </Box>

      <Box sx={styles.footer}>
        <Box />
        <Button variant="contained" sx={styles.continueButton} onClick={handleNext} disabled={!isProfileComplete}>
          Continue
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
              <Box sx={{ ...styles.colorBar, backgroundColor: agentColors[agent.type] }} />
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
        <Button sx={styles.backButton} onClick={handleBack}>
          Back
        </Button>
        <Button variant="contained" sx={styles.continueButton} onClick={handleNext} disabled={!isAgentsSelected}>
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
          Sign in to at least one agent&apos;s service. This creates a secure session for the agent to work on your
          behalf.
        </Typography>
      </Box>

      <Box sx={styles.loginContainer}>
        {/* Agents List */}
        <Box sx={styles.agentsList}>
          {selectedAgents.map((agentType) => {
            const info = getAgentInfo(agentType);
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
                onClick={() => setActiveLoginAgent(agentType)}
              >
                <Box sx={styles.agentLoginHeader}>
                  <Box
                    sx={{ ...styles.colorBar, height: '24px', marginBottom: 0 }}
                    style={{ backgroundColor: agentColors[agentType] }}
                  />
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
            <AgentAuthTerminal
              agentType={activeLoginAgent}
              onAuthComplete={() => {
                setLoginStatuses((prev) => ({ ...prev, [activeLoginAgent]: 'authenticated' }));
                enqueueSnackbar(`${getAgentInfo(activeLoginAgent).name} authenticated!`, { variant: 'success' });

                // Move to next agent if available
                const currentIndex = selectedAgents.indexOf(activeLoginAgent);
                if (currentIndex < selectedAgents.length - 1) {
                  setActiveLoginAgent(selectedAgents[currentIndex + 1]);
                }
              }}
              onCancel={() => {
                setLoginStatuses((prev) => ({ ...prev, [activeLoginAgent]: 'error' }));
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
        <Button sx={styles.backButton} onClick={handleBack}>
          Back
        </Button>
        <Button variant="contained" sx={styles.continueButton} onClick={handleNext} disabled={!isAgentsAuthenticated}>
          {allAgentsAuthenticated ? 'Continue' : `Continue (${authenticatedCount}/${selectedAgents.length})`}
        </Button>
      </Box>
    </>
  );

  const renderCompleteStep = () => (
    <Box sx={styles.completeContainer}>
      <Typography sx={styles.completeIcon}>🎉</Typography>
      <Typography sx={styles.completeTitle}>You&apos;re all set!</Typography>
      <Typography sx={styles.completeSubtitle}>Your profile and AI agents are configured and ready to use.</Typography>

      <Box sx={{ maxWidth: '400px', margin: '0 auto', marginBottom: '32px' }}>
        {selectedAgents.map((agentType) => {
          const info = getAgentInfo(agentType);
          const isAuthenticated = loginStatuses[agentType] === 'authenticated';
          return (
            <Box key={agentType} sx={styles.summaryCard}>
              <Box
                sx={{ ...styles.colorBar, height: '24px', marginBottom: 0 }}
                style={{ backgroundColor: agentColors[agentType] }}
              />
              <Typography sx={styles.summaryText}>{info.name}</Typography>
              <Typography
                sx={{ marginLeft: 'auto', fontSize: '12px', color: isAuthenticated ? 'success.main' : 'warning.main' }}
              >
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
        <Button variant="contained" sx={styles.continueButton} onClick={handleComplete} disabled={isSubmitting}>
          {isSubmitting ? 'Saving...' : isEditMode ? 'Save Changes' : 'Get Started'}
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
