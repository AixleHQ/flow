import type { AnalyticsPeriod, AnalyticsScope } from 'features/project-analytics/api/projectAnalyticsApi';
import { baseApi, QueryTag } from 'shared/api';
import { Routes } from 'shared/routes';

export interface WorkflowCostRow {
  workflowId: number;
  workflowName: string;
  totalCostCents: number;
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
  runCount: number;
}

export interface WorkflowCostTimeSeriesPoint {
  date: string;
  costCents: number;
  totalTokens: number;
}

export interface WorkflowCostTotals {
  totalCostCents: number;
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
  workflowCount: number;
  avgCostCentsPerWorkflow: number;
}

export interface WorkflowCostAnalyticsResponse {
  workflows: WorkflowCostRow[];
  timeSeries: WorkflowCostTimeSeriesPoint[];
  totals: WorkflowCostTotals;
}

export interface WorkflowCostAnalyticsParams {
  projectId: number;
  scope: AnalyticsScope;
  period: AnalyticsPeriod;
}

export const workflowCostAnalyticsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getWorkflowCostAnalytics: builder.query<WorkflowCostAnalyticsResponse, WorkflowCostAnalyticsParams>({
      query: ({ projectId, scope, period }) => ({
        url: Routes.backend.apiV1CompanyProjectStatisticWorkflowCostsPath(projectId),
        method: 'GET',
        params: { scope, period },
      }),
      providesTags: [QueryTag.WorkflowCostAnalytics],
    }),
  }),
});

export const { useGetWorkflowCostAnalyticsQuery } = workflowCostAnalyticsApi;
