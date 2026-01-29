import type { IProject } from 'entities/project';
import type { ApiCollectionResponse } from 'shared/api';
import { baseApi, QueryTag, providesListTag } from 'shared/api';

export const projectsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    projects: builder.query<ApiCollectionResponse<IProject>, void>({
      query: () => ({ url: '/api/v1/projects', method: 'GET' }),
      providesTags: (result) => providesListTag(result?.items, QueryTag.Project),
    }),
  }),
});

export const { useProjectsQuery } = projectsApi;
