import { baseApi } from 'shared/api';
import type { ApiCollectionResponse } from 'shared/api';
import { QueryTag, providesListTag } from 'shared/api';

import type { IProject } from 'entities/project';

export const projectsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    projects: builder.query<ApiCollectionResponse<IProject>, void>({
      query: () => '/projects',
      providesTags: (result) => providesListTag(result?.data, QueryTag.Project),
    }),
  }),
});

export const { useProjectsQuery } = projectsApi;
