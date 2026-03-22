import { baseApi, QueryTag } from 'shared/api';
import type { AnalyticsPeriod, AnalyticsScope } from 'shared/api/analyticsTypes';
import { Routes } from 'shared/routes';

export type { AnalyticsScope, AnalyticsPeriod };

export interface ProjectAnalyticsSummary {
  totalSessions: number;
  totalCostCents: number;
  totalTokens: number;
  avgCostCentsPerSession: number;
  workflowsRun: number;
}

export interface ProjectAnalyticsParams {
  projectId: number;
  scope: AnalyticsScope;
  period: AnalyticsPeriod;
}

export const projectAnalyticsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getProjectAnalytics: builder.query<ProjectAnalyticsSummary, ProjectAnalyticsParams>({
      query: ({ projectId, scope, period }) => ({
        url: Routes.backend.apiV1CompanyProjectStatisticAnalyticsPath(projectId),
        method: 'GET',
        params: { scope, period },
      }),
      providesTags: [QueryTag.ProjectAnalytics],
    }),
  }),
});

export const { useGetProjectAnalyticsQuery } = projectAnalyticsApi;
