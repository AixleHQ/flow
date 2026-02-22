import { baseApi, QueryTag } from 'shared/api';
import { Routes } from 'shared/routes';

import type { Integration, CreateGithubIntegrationRequest } from '../lib/types';

interface IntegrationsResponse {
  items: Integration[];
}

export const integrationsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getCompanyIntegrations: builder.query<Integration[], void>({
      query: () => ({
        url: Routes.backend.apiV1CompanyIntegrationsPath(),
        method: 'GET',
      }),
      transformResponse: (response: Integration[] | IntegrationsResponse) => {
        return Array.isArray(response) ? response : response.items;
      },
      providesTags: [QueryTag.Integrations],
    }),

    createGithubIntegration: builder.mutation<Integration, CreateGithubIntegrationRequest>({
      query: (data) => ({
        url: Routes.backend.apiV1CompanyIntegrationsPath(),
        method: 'POST',
        data: { installationId: data.installationId },
      }),
      invalidatesTags: [QueryTag.Integrations],
    }),

    deleteIntegration: builder.mutation<void, number>({
      query: (id) => ({
        url: Routes.backend.apiV1CompanyIntegrationPath(id),
        method: 'DELETE',
      }),
      invalidatesTags: [QueryTag.Integrations],
    }),
  }),
});

export const { useGetCompanyIntegrationsQuery, useCreateGithubIntegrationMutation, useDeleteIntegrationMutation } =
  integrationsApi;
