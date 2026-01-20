import { baseApi, QueryTag } from 'shared/api';

import type { LoginFormData } from '../lib/schema';

const API_V1_SESSIONS_PATH = '/api/v1/sessions';

export const loginApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    login: builder.mutation<void, LoginFormData>({
      query: (data) => ({
        url: API_V1_SESSIONS_PATH,
        method: 'POST',
        data: { user: data },
      }),
      invalidatesTags: [QueryTag.CurrentUser],
    }),
    logout: builder.mutation<void, void>({
      query: () => ({
        url: API_V1_SESSIONS_PATH,
        method: 'DELETE',
      }),
      invalidatesTags: [QueryTag.CurrentUser],
    }),
  }),
});

export const { useLoginMutation, useLogoutMutation } = loginApi;
