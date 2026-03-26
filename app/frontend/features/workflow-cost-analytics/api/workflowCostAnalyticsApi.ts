import { baseApi, QueryTag } from 'shared/api';
import type { AnalyticsPeriod, AnalyticsScope } from 'shared/api/analyticsTypes';
import { Routes } from 'shared/routes';

export interface WorkflowCostRow {
  workflowId: number;
  workflowName: string;
  totalCostCents: number;
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
  runCount: number;
  totalDurationSeconds: number;
  avgDurationSeconds: number;
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
  tags?: string[];
  taskType?: string;
}

export const workflowCostAnalyticsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getWorkflowCostAnalytics: builder.query<WorkflowCostAnalyticsResponse, WorkflowCostAnalyticsParams>({
      query: ({ projectId, scope, period, tags, taskType }) => ({
        url: Routes.backend.apiV1CompanyProjectStatisticWorkflowCostsPath(projectId),
        method: 'GET',
        params: { scope, period, 'tags[]': tags, task_type: taskType },
      }),
      providesTags: [QueryTag.WorkflowCostAnalytics],
    }),
  }),
});

export const { useGetWorkflowCostAnalyticsQuery } = workflowCostAnalyticsApi;
