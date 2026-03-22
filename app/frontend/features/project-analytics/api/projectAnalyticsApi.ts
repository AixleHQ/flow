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
    getAgentActivity: builder.query<AgentActivityData, ProjectAnalyticsParams>({
      query: ({ projectId, scope, period }) => ({
        url: Routes.backend.agentActivityApiV1CompanyProjectStatisticAnalyticsPath(projectId),
        method: 'GET',
        params: { scope, period },
      }),
      providesTags: [QueryTag.ProjectAnalytics],
    }),
  }),
});

export const { useGetProjectAnalyticsQuery, useGetAgentActivityQuery } = projectAnalyticsApi;
