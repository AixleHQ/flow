import { baseApi, QueryTag } from 'shared/api';
import { Routes } from 'shared/routes';

export interface AgentSessionStats {
  rank: number;
  name: string;
  agentType: string;
  sessionsCount: number;
  totalCostCents: number;
}

export const topAgentsBySessionsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getTopAgentsBySessions: builder.query<AgentSessionStats[], { limit?: number } | void>({
      query: (params) => ({
        url: Routes.backend.apiV1CompanyStatisticTopAgentsPath(),
        method: 'GET',
        params: params ?? {},
      }),
      transformResponse: (response: { topAgents: AgentSessionStats[] }) => response.topAgents,
      providesTags: [QueryTag.TopAgentsSessions],
    }),
  }),
});

export const { useGetTopAgentsBySessionsQuery } = topAgentsBySessionsApi;
