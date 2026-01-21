import { baseApi, QueryTag } from 'shared/api';

import type { AgentType, IAgentsResponse, ICreateSessionResponse } from '../lib/types';

export const workspaceApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getAgents: builder.query<IAgentsResponse, void>({
      query: () => ({
        url: '/api/v1/terminal_sessions/agents',
        method: 'GET',
      }),
      providesTags: [QueryTag.AgentCredentials],
    }),
    createSession: builder.mutation<ICreateSessionResponse, { agentType: AgentType }>({
      query: ({ agentType }) => ({
        url: '/api/v1/terminal_sessions',
        method: 'POST',
        data: { agent_type: agentType },
      }),
    }),
    getSession: builder.query<ICreateSessionResponse, { sessionId: string; agentType: AgentType }>({
      query: ({ sessionId, agentType }) => ({
        url: `/api/v1/terminal_sessions/${sessionId}`,
        method: 'GET',
        params: { agent_type: agentType },
      }),
    }),
    stopSession: builder.mutation<void, { sessionId: string; agentType: AgentType }>({
      query: ({ sessionId, agentType }) => ({
        url: `/api/v1/terminal_sessions/${sessionId}`,
        method: 'DELETE',
        params: { agent_type: agentType },
      }),
    }),
  }),
});

export const { useGetAgentsQuery, useCreateSessionMutation, useGetSessionQuery, useStopSessionMutation } = workspaceApi;
