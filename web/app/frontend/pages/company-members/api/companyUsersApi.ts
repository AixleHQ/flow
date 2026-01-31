import { baseApi, QueryTag, type ApiResponse, type PaginatedResponse } from 'shared/api';

import type {
  CompanyUser,
  CreateCompanyUserRequest,
  UpdateCompanyUserRequest,
  CompanyUsersFilters,
} from '../lib/types';
import { Routes } from '../../../shared/routes';

// Build query params from filters
function buildQueryParams(filters?: CompanyUsersFilters): Record<string, string | number | undefined> {
  const params: Record<string, string | number | undefined> = {
    page: filters?.page,
    per_page: filters?.perPage,
  };

  if (filters?.role) {
    params['q[role_eq]'] = filters.role;
  }
  if (filters?.state) {
    params['q[state_eq]'] = filters.state;
  }
  if (filters?.search) {
    params['q[email_or_name_cont]'] = filters.search;
  }

  return params;
}

export const companyUsersApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getCompanyUsers: builder.query<PaginatedResponse<CompanyUser>, CompanyUsersFilters | void>({
      query: (filters) => ({
        url: Routes.backend.apiV1CompanyUsersPath(),
        method: 'GET',
        params: buildQueryParams(filters ?? {}),
      }),
      providesTags: [QueryTag.CompanyUsers],
    }),
    createCompanyUser: builder.mutation<CompanyUser, CreateCompanyUserRequest>({
      query: (data) => ({
        url: Routes.backend.apiV1CompanyUsersPath(),
        method: 'POST',
        data: { user: data },
      }),
      transformResponse: (response: ApiResponse<CompanyUser>) => response.data,
      invalidatesTags: [QueryTag.CompanyUsers],
    }),
    updateCompanyUser: builder.mutation<CompanyUser, UpdateCompanyUserRequest>({
      query: ({ id, ...data }) => ({
        url: Routes.backend.apiV1CompanyUserPath(id),
        method: 'PATCH',
        data: { user: data },
      }),
      transformResponse: (response: ApiResponse<CompanyUser>) => response.data,
      invalidatesTags: [QueryTag.CompanyUsers],
    }),
    deleteCompanyUser: builder.mutation<void, number>({
      query: (id) => ({
        url: Routes.backend.apiV1CompanyUserPath(id),
        method: 'DELETE',
      }),
      invalidatesTags: [QueryTag.CompanyUsers],
    }),
  }),
});

export const {
  useGetCompanyUsersQuery,
  useCreateCompanyUserMutation,
  useUpdateCompanyUserMutation,
  useDeleteCompanyUserMutation,
} = companyUsersApi;
