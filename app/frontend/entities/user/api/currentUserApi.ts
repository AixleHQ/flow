import { baseApi, QueryTag, type ApiResponse } from 'shared/api';

import type { AgentType, CurrentUserResponse, OnboardingEvent, UserPosition } from '../model/types';

interface IUpdateCurrentUserRequest {
  currentUser: {
    name?: string;
    password?: string;
    passwordConfirmation?: string;
    position?: UserPosition;
    preferredAgentLanguage?: string;
    selectedAgents?: AgentType[];
    onboardingStateEvent?: OnboardingEvent;
    defaultAgentCredentialId?: number | null;
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
