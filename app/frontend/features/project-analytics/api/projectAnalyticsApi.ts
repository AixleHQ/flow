import { baseApi, QueryTag } from 'shared/api';
import { Routes } from 'shared/routes';

export type AnalyticsScope = 'user' | 'project' | 'company';
export type AnalyticsPeriod = '7d' | '30d' | '90d' | '1y';

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
