import { baseApi, QueryTag } from 'shared/api';
import { Routes } from 'shared/routes';

export interface PlatformSummary {
  sessionsLaunched: number;
  totalSpendCents: number;
  workflowsCount: number;
  boardTasksCount: number;
}

export const platformSummaryApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getPlatformSummary: builder.query<PlatformSummary, { projectId: number }>({
      query: ({ projectId }) => ({
        url: Routes.backend.apiV1CompanyProjectStatisticOverviewPath(projectId),
        method: 'GET',
      }),
      providesTags: [QueryTag.PlatformSummary],
    }),
  }),
});

export const { useGetPlatformSummaryQuery } = platformSummaryApi;
