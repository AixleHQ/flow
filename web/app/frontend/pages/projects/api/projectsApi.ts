import type { IProject } from 'entities/project';
import type { ApiCollectionResponse, ApiResponse } from 'shared/api';
import { baseApi, QueryTag } from 'shared/api';
import { Routes } from 'shared/routes';

export interface CreateProjectRequest {
  name: string;
  description?: string;
}

export const projectsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    projects: builder.query<ApiCollectionResponse<IProject>, void>({
      query: () => ({ url: Routes.backend.apiV1CompanyProjectsPath(), method: 'GET' }),
      providesTags: (result) =>
        result?.items
          ? [{ type: QueryTag.Project, id: 'LIST' }, ...result.items.map(({ id }) => ({ type: QueryTag.Project, id }))]
          : [{ type: QueryTag.Project, id: 'LIST' }],
    }),
    createProject: builder.mutation<ApiResponse<IProject>, CreateProjectRequest>({
      query: (data) => ({
        url: Routes.backend.apiV1CompanyProjectsPath(),
        method: 'POST',
        data: { project: data },
      }),
      invalidatesTags: [{ type: QueryTag.Project, id: 'LIST' }],
    }),
  }),
});

export const { useProjectsQuery, useCreateProjectMutation } = projectsApi;
