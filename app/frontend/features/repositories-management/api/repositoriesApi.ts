import { baseApi, QueryTag } from 'shared/api';
import { Routes } from 'shared/routes';

import type {
  Repository,
  AvailableRepo,
  CreateRepositoryRequest,
  UpdateRepositoryRequest,
  WebhookInfo,
} from '../lib/types';

interface RepositoriesResponse {
  items: Repository[];
}

interface AvailableReposResponse {
  items: AvailableRepo[];
}

interface BranchesResponse {
  items: string[];
}

export const repositoriesApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getCompanyRepositories: builder.query<Repository[], void>({
      query: () => ({
        url: Routes.backend.apiV1CompanyRepositoriesPath(),
        method: 'GET',
      }),
      transformResponse: (response: Repository[] | RepositoriesResponse) =>
        Array.isArray(response) ? response : response.items,
      providesTags: [QueryTag.Repositories],
    }),

    getProjectRepositories: builder.query<Repository[], number>({
      query: (projectId) => ({
        url: Routes.backend.apiV1CompanyProjectRepositoriesPath(projectId),
        method: 'GET',
      }),
      transformResponse: (response: Repository[] | RepositoriesResponse) =>
        Array.isArray(response) ? response : response.items,
      providesTags: [QueryTag.Repositories],
    }),

    getAvailableRepositories: builder.query<AvailableRepo[], { integrationId: number; projectId?: number }>({
      query: ({ integrationId, projectId }) => ({
        url: projectId
          ? Routes.backend.availableApiV1CompanyProjectRepositoriesPath(projectId)
          : Routes.backend.availableApiV1CompanyRepositoriesPath(),
        method: 'GET',
        params: { integrationId },
      }),
      transformResponse: (response: AvailableRepo[] | AvailableReposResponse) =>
        Array.isArray(response) ? response : response.items,
      providesTags: [QueryTag.Repositories],
    }),

    getBranches: builder.query<string[], { integrationId: number; fullName: string; projectId?: number }>({
      query: ({ integrationId, fullName, projectId }) => ({
        url: projectId
          ? Routes.backend.branchesApiV1CompanyProjectRepositoriesPath(projectId)
          : Routes.backend.branchesApiV1CompanyRepositoriesPath(),
        method: 'GET',
        params: { integrationId, fullName },
      }),
      transformResponse: (response: string[] | BranchesResponse) =>
        Array.isArray(response) ? response : response.items,
      providesTags: [QueryTag.Repositories],
    }),

    createCompanyRepository: builder.mutation<Repository, CreateRepositoryRequest>({
      query: ({ integrationId, fullName, sourceBranch, purpose }) => ({
        url: Routes.backend.apiV1CompanyRepositoriesPath(),
        method: 'POST',
        data: { integrationId, fullName, sourceBranch: sourceBranch || undefined, purpose: purpose || undefined },
      }),
      transformResponse: (response: { data: Repository }) => response.data,
      invalidatesTags: [QueryTag.Repositories],
    }),

    createProjectRepository: builder.mutation<Repository, { projectId: number } & CreateRepositoryRequest>({
      query: ({ projectId, integrationId, fullName, sourceBranch, purpose }) => ({
        url: Routes.backend.apiV1CompanyProjectRepositoriesPath(projectId),
        method: 'POST',
        data: { integrationId, fullName, sourceBranch: sourceBranch || undefined, purpose: purpose || undefined },
      }),
      transformResponse: (response: { data: Repository }) => response.data,
      invalidatesTags: [QueryTag.Repositories],
    }),

    updateCompanyRepository: builder.mutation<Repository, { id: number } & UpdateRepositoryRequest>({
      query: ({ id, ...data }) => ({
        url: Routes.backend.apiV1CompanyRepositoryPath(id),
        method: 'PATCH',
        data: { repository: data },
      }),
      invalidatesTags: [QueryTag.Repositories],
    }),

    updateProjectRepository: builder.mutation<Repository, { projectId: number; id: number } & UpdateRepositoryRequest>({
      query: ({ projectId, id, ...data }) => ({
        url: Routes.backend.apiV1CompanyProjectRepositoryPath(projectId, id),
        method: 'PATCH',
        data: { repository: data },
      }),
      invalidatesTags: [QueryTag.Repositories],
    }),

    deleteCompanyRepository: builder.mutation<void, number>({
      query: (id) => ({
        url: Routes.backend.apiV1CompanyRepositoryPath(id),
        method: 'DELETE',
      }),
      invalidatesTags: [QueryTag.Repositories],
    }),

    deleteProjectRepository: builder.mutation<void, { projectId: number; id: number }>({
      query: ({ projectId, id }) => ({
        url: Routes.backend.apiV1CompanyProjectRepositoryPath(projectId, id),
        method: 'DELETE',
      }),
      invalidatesTags: [QueryTag.Repositories],
    }),

    getWebhookInfo: builder.query<WebhookInfo, { id: number; projectId?: number }>({
      query: ({ id, projectId }) => ({
        url: projectId
          ? Routes.backend.webhookInfoApiV1CompanyProjectRepositoryPath(projectId, id)
          : Routes.backend.webhookInfoApiV1CompanyRepositoryPath(id),
        method: 'GET',
      }),
    }),
  }),
});

export const {
  useGetCompanyRepositoriesQuery,
  useGetProjectRepositoriesQuery,
  useGetAvailableRepositoriesQuery,
  useGetBranchesQuery,
  useUpdateCompanyRepositoryMutation,
  useUpdateProjectRepositoryMutation,
  useCreateCompanyRepositoryMutation,
  useCreateProjectRepositoryMutation,
  useDeleteCompanyRepositoryMutation,
  useDeleteProjectRepositoryMutation,
  useGetWebhookInfoQuery,
} = repositoriesApi;
