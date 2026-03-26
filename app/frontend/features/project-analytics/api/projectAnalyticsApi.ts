import { baseApi, QueryTag } from 'shared/api';
import type { AnalyticsPeriod, AnalyticsScope } from 'shared/api/analyticsTypes';
import { Routes } from 'shared/routes';

export interface AnalyticsFilterOptions {
  tags: string[];
  taskTypes: string[];
}

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
  tags?: string[];
  taskType?: string;
}

export interface AgentSessionCount {
  agentType: string;
  sessions: number;
  costCents: number;
  tokens: number;
}

export interface AgentActivityPoint {
  date: string;
  agentType: string;
  sessions: number;
}

export interface AgentActivityData {
  agentTypes: string[];
  sessionsByAgent: AgentSessionCount[];
  activityOverTime: AgentActivityPoint[];
}

export interface SessionSourceRow {
  sessionType: string;
  label: string;
  count: number;
}

export interface SessionSourceBreakdownData {
  sources: SessionSourceRow[];
}

export interface SessionDurationBucket {
  range: string;
  count: number;
}

export interface SessionDurationDistributionData {
  buckets: SessionDurationBucket[];
}

export interface CostTokenTimeSeriesPoint {
  date: string;
  costCents: number;
  totalTokens: number;
}

export interface CostTokenTotals {
  totalCostCents: number;
  totalTokens: number;
  avgCostCentsPerSession: number;
}

export interface CostTokenUsageData {
  timeSeries: CostTokenTimeSeriesPoint[];
  totals: CostTokenTotals;
}

export const projectAnalyticsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getAnalyticsFilterOptions: builder.query<AnalyticsFilterOptions, number>({
      query: (projectId) => ({
        url: Routes.backend.filterOptionsApiV1CompanyProjectStatisticAnalyticsPath(projectId),
        method: 'GET',
      }),
      providesTags: [QueryTag.ProjectAnalytics],
    }),
    getProjectAnalytics: builder.query<ProjectAnalyticsSummary, ProjectAnalyticsParams>({
      query: ({ projectId, scope, period, tags, taskType }) => ({
        url: Routes.backend.apiV1CompanyProjectStatisticAnalyticsPath(projectId),
        method: 'GET',
        params: { scope, period, tags, task_type: taskType },
      }),
      providesTags: [QueryTag.ProjectAnalytics],
    }),
    getAgentActivity: builder.query<AgentActivityData, ProjectAnalyticsParams>({
      query: ({ projectId, scope, period, tags, taskType }) => ({
        url: Routes.backend.agentActivityApiV1CompanyProjectStatisticAnalyticsPath(projectId),
        method: 'GET',
        params: { scope, period, tags, task_type: taskType },
      }),
      providesTags: [QueryTag.ProjectAnalytics],
    }),
    getSessionSourceBreakdown: builder.query<SessionSourceBreakdownData, ProjectAnalyticsParams>({
      query: ({ projectId, scope, period, tags, taskType }) => ({
        url: Routes.backend.sessionSourceBreakdownApiV1CompanyProjectStatisticAnalyticsPath(projectId),
        method: 'GET',
        params: { scope, period, tags, task_type: taskType },
      }),
      providesTags: [QueryTag.ProjectAnalytics],
    }),
    getSessionDurationDistribution: builder.query<SessionDurationDistributionData, ProjectAnalyticsParams>({
      query: ({ projectId, scope, period, tags, taskType }) => ({
        url: Routes.backend.sessionDurationDistributionApiV1CompanyProjectStatisticAnalyticsPath(projectId),
        method: 'GET',
        params: { scope, period, tags, task_type: taskType },
      }),
      providesTags: [QueryTag.ProjectAnalytics],
    }),
    getCostTokenUsage: builder.query<CostTokenUsageData, ProjectAnalyticsParams>({
      query: ({ projectId, scope, period, tags, taskType }) => ({
        url: Routes.backend.costTokenUsageApiV1CompanyProjectStatisticAnalyticsPath(projectId),
        method: 'GET',
        params: { scope, period, tags, task_type: taskType },
      }),
      providesTags: [QueryTag.ProjectAnalytics],
    }),
  }),
});

export const {
  useGetAnalyticsFilterOptionsQuery,
  useGetProjectAnalyticsQuery,
  useGetAgentActivityQuery,
  useGetSessionSourceBreakdownQuery,
  useGetSessionDurationDistributionQuery,
  useGetCostTokenUsageQuery,
} = projectAnalyticsApi;
