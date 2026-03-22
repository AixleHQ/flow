import { baseApi, QueryTag } from 'shared/api';
import { Routes } from 'shared/routes';

export interface AgentSessionStats {
  rank: number;
  name: string;
  agent_type: string;
  sessions_count: number;
  total_cost_cents: number;
}

export const topAgentsBySessionsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getTopAgentsBySessions: builder.query<AgentSessionStats[], { limit?: number } | void>({
      query: (params) => ({
        url: Routes.backend.apiV1CompanyStatisticTopAgentsPath(),
        method: 'GET',
        params: params ?? {},
      }),
      providesTags: [QueryTag.TopAgentsSessions],
    }),
  }),
});

export const { useGetTopAgentsBySessionsQuery } = topAgentsBySessionsApi;
