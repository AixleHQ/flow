import { baseApi, QueryTag } from 'shared/api';
import { Routes } from 'shared/routes';

export interface WorkflowRunStats {
  completed: number;
  inProgress: number;
  failed: number;
  queued: number;
  total: number;
}

export const workflowRunStatsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getWorkflowRunStats: builder.query<WorkflowRunStats, void>({
      query: () => ({
        url: Routes.backend.apiV1CompanyWorkflowRunStatsPath(),
        method: 'GET',
      }),
      providesTags: [QueryTag.WorkflowRunStats],
    }),
  }),
});

export const { useGetWorkflowRunStatsQuery } = workflowRunStatsApi;
