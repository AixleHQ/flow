import { baseApi, QueryTag } from 'shared/api';
import { Routes } from 'shared/routes';

import type { LoginFormData } from '../lib/schema';

export const loginApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    login: builder.mutation<void, LoginFormData>({
      query: (data) => ({
        url: Routes.backend.apiV1SessionsPath(),
        method: 'POST',
        data: { user: data },
      }),
      invalidatesTags: [QueryTag.CurrentUser],
    }),
    logout: builder.mutation<void, void>({
      query: () => ({
        url: Routes.backend.apiV1SessionsPath(),
        method: 'DELETE',
      }),
      invalidatesTags: [QueryTag.CurrentUser],
    }),
  }),
});

export const { useLoginMutation, useLogoutMutation } = loginApi;
