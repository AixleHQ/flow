import type { ApiCollectionResponse } from 'shared/api';
import { baseApi, QueryTag } from 'shared/api';
import { Routes } from 'shared/routes';

import type { IProject } from '../model/types';

export const projectsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    allProjects: builder.query<ApiCollectionResponse<IProject>, void>({
      query: () => ({ url: Routes.backend.apiV1CompanyProjectsPath(), method: 'GET' }),
      providesTags: (result) =>
        result?.items
          ? [{ type: QueryTag.Project, id: 'LIST' }, ...result.items.map(({ id }) => ({ type: QueryTag.Project, id }))]
          : [{ type: QueryTag.Project, id: 'LIST' }],
    }),
  }),
});

export const { useAllProjectsQuery } = projectsApi;
