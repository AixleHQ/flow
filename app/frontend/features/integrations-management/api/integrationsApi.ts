import { baseApi, QueryTag } from 'shared/api';
import { Routes } from 'shared/routes';

import type { Integration, CreateGithubIntegrationRequest, CreateGitlabIntegrationRequest } from '../lib/types';

interface IntegrationsResponse {
  items: Integration[];
}

const normalizeIntegrations = (response: Integration[] | IntegrationsResponse): Integration[] =>
  Array.isArray(response) ? response : response.items;

export const integrationsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getCompanyIntegrations: builder.query<Integration[], void>({
      query: () => ({
        url: Routes.backend.apiV1CompanyIntegrationsPath(),
        method: 'GET',
      }),
      transformResponse: normalizeIntegrations,
      providesTags: [QueryTag.Integrations],
    }),

    getProjectIntegrations: builder.query<Integration[], number>({
      query: (projectId) => ({
        url: Routes.backend.apiV1CompanyProjectIntegrationsPath(projectId),
        method: 'GET',
      }),
      transformResponse: normalizeIntegrations,
      providesTags: (_result, _err, projectId) => [{ type: QueryTag.ProjectIntegrations, id: String(projectId) }],
    }),

    createGithubIntegration: builder.mutation<Integration, CreateGithubIntegrationRequest>({
      query: (data) => ({
        url: Routes.backend.apiV1CompanyIntegrationsPath(),
        method: 'POST',
        data: { installationId: data.installationId },
      }),
      invalidatesTags: [QueryTag.Integrations],
    }),

    createProjectGithubIntegration: builder.mutation<
      Integration,
      { projectId: number } & CreateGithubIntegrationRequest
    >({
      query: ({ projectId, installationId }) => ({
        url: Routes.backend.apiV1CompanyProjectIntegrationsPath(projectId),
        method: 'POST',
        data: { installationId },
      }),
      invalidatesTags: (_result, _err, { projectId }) => [
        { type: QueryTag.ProjectIntegrations, id: String(projectId) },
      ],
    }),

    createGitlabIntegration: builder.mutation<Integration, CreateGitlabIntegrationRequest>({
      query: (data) => ({
        url: Routes.backend.apiV1CompanyIntegrationsPath(),
        method: 'POST',
        data: { provider: 'gitlab', personal_access_token: data.personalAccessToken },
      }),
      invalidatesTags: [QueryTag.Integrations],
    }),

    createProjectGitlabIntegration: builder.mutation<
      Integration,
      { projectId: number } & CreateGitlabIntegrationRequest
    >({
      query: ({ projectId, personalAccessToken }) => ({
        url: Routes.backend.apiV1CompanyProjectIntegrationsPath(projectId),
        method: 'POST',
        data: { provider: 'gitlab', personal_access_token: personalAccessToken },
      }),
      invalidatesTags: (_result, _err, { projectId }) => [
        { type: QueryTag.ProjectIntegrations, id: String(projectId) },
      ],
    }),

    deleteIntegration: builder.mutation<void, number>({
      query: (id) => ({
        url: Routes.backend.apiV1CompanyIntegrationPath(id),
        method: 'DELETE',
      }),
      invalidatesTags: [QueryTag.Integrations],
    }),

    deleteProjectIntegration: builder.mutation<void, { projectId: number; id: number }>({
      query: ({ projectId, id }) => ({
        url: Routes.backend.apiV1CompanyProjectIntegrationPath(projectId, id),
        method: 'DELETE',
      }),
      invalidatesTags: (_result, _err, { projectId }) => [
        { type: QueryTag.ProjectIntegrations, id: String(projectId) },
      ],
    }),
  }),
});

export const {
  useGetCompanyIntegrationsQuery,
  useGetProjectIntegrationsQuery,
  useCreateGithubIntegrationMutation,
  useCreateProjectGithubIntegrationMutation,
  useCreateGitlabIntegrationMutation,
  useCreateProjectGitlabIntegrationMutation,
  useDeleteIntegrationMutation,
  useDeleteProjectIntegrationMutation,
} = integrationsApi;
