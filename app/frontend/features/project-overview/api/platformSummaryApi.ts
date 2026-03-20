import { baseApi, QueryTag } from 'shared/api';
import { Routes } from 'shared/routes';

export interface PlatformSummary {
  sessionsLaunched: number;
  totalSpendCents: number;
  workflowsCount: number;
  boardTasksCount: number;
  usersCount: number;
  agentsCount: number;
  projectsCount: number;
}

export const platformSummaryApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getPlatformSummary: builder.query<PlatformSummary, void>({
      query: () => ({
        url: Routes.backend.apiV1CompanyOverviewPath(),
        method: 'GET',
      }),
      providesTags: [QueryTag.PlatformSummary],
    }),
  }),
});

export const { useGetPlatformSummaryQuery } = platformSummaryApi;
