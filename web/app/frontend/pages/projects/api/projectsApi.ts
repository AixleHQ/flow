import type { IProject } from 'entities/project';
import type { ApiCollectionResponse } from 'shared/api';
import { baseApi, QueryTag } from 'shared/api';

export const projectsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    projects: builder.query<ApiCollectionResponse<IProject>, void>({
      query: () => ({ url: '/api/v1/projects', method: 'GET' }),
      providesTags: (result) =>
        result?.items
          ? [{ type: QueryTag.Project, id: 'LIST' }, ...result.items.map(({ id }) => ({ type: QueryTag.Project, id }))]
          : [{ type: QueryTag.Project, id: 'LIST' }],
    }),
  }),
});

export const { useProjectsQuery } = projectsApi;
