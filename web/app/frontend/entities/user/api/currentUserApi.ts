import { baseApi, QueryTag, type ApiResponse } from 'shared/api';

import type { AgentType, CurrentUserResponse, OnboardingEvent, UserPosition } from '../model/types';

interface IUpdateCurrentUserRequest {
  currentUser: {
    name?: string;
    password?: string;
    passwordConfirmation?: string;
    position?: UserPosition;
    preferredAgentLanguage?: string;
    // Agents selected in Step 2 (before auth)
    selectedAgents?: AgentType[];
    // Trigger onboarding state transition: go_next, go_previous, complete
    onboardingStateEvent?: OnboardingEvent;
    // Note: configuredAgents is read-only, derived from AgentCredentials
  };
}

export const currentUserApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getCurrentUser: builder.query<CurrentUserResponse, void>({
      query: () => ({
        url: '/api/v1/current_user',
        method: 'GET',
      }),
      transformResponse: (response: ApiResponse<CurrentUserResponse>) => response.data,
      providesTags: [QueryTag.CurrentUser],
    }),
    updateCurrentUser: builder.mutation<CurrentUserResponse, IUpdateCurrentUserRequest>({
      query: (data) => ({
        url: '/api/v1/current_user',
        method: 'PATCH',
        data,
      }),
      transformResponse: (response: ApiResponse<CurrentUserResponse>) => response.data,
      invalidatesTags: [QueryTag.CurrentUser],
    }),
  }),
});

export const { useGetCurrentUserQuery, useUpdateCurrentUserMutation } = currentUserApi;
