// Onboarding API is deprecated - all logic moved to currentUserApi
// This file is kept for backwards compatibility but should not be used

import { useUpdateCurrentUserMutation } from 'entities/user';

/**
 * @deprecated Use useUpdateCurrentUserMutation from currentUserApi instead
 */
export const useCompleteOnboardingMutation = useUpdateCurrentUserMutation;

/**
 * @deprecated Onboarding data is now part of currentUser response
 */
export const useGetOnboardingQuery = () => {
  console.warn('useGetOnboardingQuery is deprecated. Use useGetCurrentUserQuery instead.');
  return { data: undefined, isLoading: false };
};
