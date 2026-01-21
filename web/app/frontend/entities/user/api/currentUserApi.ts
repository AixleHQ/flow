import { baseApi, QueryTag } from 'shared/api';

import type { CurrentUserResponse } from '../model/types';

export const currentUserApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getCurrentUser: builder.query<CurrentUserResponse, void>({
      query: () => ({
        url: '/api/v1/current_user',
        method: 'GET',
      }),
      providesTags: [QueryTag.CurrentUser],
    }),
  }),
});

export const { useGetCurrentUserQuery } = currentUserApi;
