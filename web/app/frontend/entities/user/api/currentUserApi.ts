import { baseApi, QueryTag } from 'shared/api';

import type { AgentType, CurrentUserResponse, UserPosition } from '../model/types';

interface IUpdateCurrentUserRequest {
  currentUser: {
    name?: string;
    password?: string;
    passwordConfirmation?: string;
    position?: UserPosition;
    preferredAgentLanguage?: string;
    configuredAgents?: AgentType[];
  };
}

export const currentUserApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getCurrentUser: builder.query<CurrentUserResponse, void>({
      query: () => ({
        url: '/api/v1/current_user',
        method: 'GET',
      }),
      providesTags: [QueryTag.CurrentUser],
    }),
    updateCurrentUser: builder.mutation<CurrentUserResponse, IUpdateCurrentUserRequest>({
      query: (data) => ({
        url: '/api/v1/current_user',
        method: 'PATCH',
        data,
      }),
      invalidatesTags: [QueryTag.CurrentUser],
    }),
  }),
});

export const { useGetCurrentUserQuery, useUpdateCurrentUserMutation } = currentUserApi;
