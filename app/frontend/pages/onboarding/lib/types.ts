import type { AgentType } from 'entities/user';

export interface Agent {
  type: AgentType;
  name: string;
  description: string;
  icon: string;
  configured: boolean;
  selected: boolean;
}

export interface OnboardingResponse {
  agents: Agent[];
  userSelected: AgentType[];
  onboardingCompleted: boolean;
}

export interface CompleteOnboardingRequest {
  agents: AgentType[];
}

export interface CompleteOnboardingResponse {
  message: string;
  selectedAgents: AgentType[];
  nextStep: string;
}
