import { baseApi, QueryTag } from 'shared/api';
import { Routes } from 'shared/routes';

import type { Agent, CreateAgentRequest, UpdateAgentRequest } from '../lib/types';

interface AgentsResponse {
  items: Agent[];
}

export const agentsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    // Company-level agents
    getCompanyAgents: builder.query<Agent[], void>({
      query: () => ({
        url: Routes.backend.apiV1CompanyAgentsPath(),
        method: 'GET',
      }),
      transformResponse: (response: Agent[] | AgentsResponse) => {
        return Array.isArray(response) ? response : response.items;
      },
      providesTags: [QueryTag.Agents],
    }),

    // Project-level agents (merged list)
    getProjectAgents: builder.query<Agent[], number>({
      query: (projectId) => ({
        url: Routes.backend.apiV1CompanyProjectAgentsPath(projectId),
        method: 'GET',
      }),
      transformResponse: (response: Agent[] | AgentsResponse) => {
        return Array.isArray(response) ? response : response.items;
      },
      providesTags: [QueryTag.Agents],
    }),

    // Create agent (company or project level)
    createCompanyAgent: builder.mutation<Agent, CreateAgentRequest>({
      query: (data) => ({
        url: Routes.backend.apiV1CompanyAgentsPath(),
        method: 'POST',
        data: { agent: data },
      }),
      invalidatesTags: [QueryTag.Agents],
    }),

    createProjectAgent: builder.mutation<Agent, { projectId: number } & CreateAgentRequest>({
      query: ({ projectId, ...data }) => ({
        url: Routes.backend.apiV1CompanyProjectAgentsPath(projectId),
        method: 'POST',
        data: { agent: data },
      }),
      invalidatesTags: [QueryTag.Agents],
    }),

    // Update agent
    updateCompanyAgent: builder.mutation<Agent, UpdateAgentRequest>({
      query: ({ id, ...data }) => ({
        url: Routes.backend.apiV1CompanyAgentPath(id),
        method: 'PATCH',
        data: { agent: data },
      }),
      invalidatesTags: [QueryTag.Agents],
    }),

    updateProjectAgent: builder.mutation<Agent, { projectId: number } & UpdateAgentRequest>({
      query: ({ projectId, id, ...data }) => ({
        url: Routes.backend.apiV1CompanyProjectAgentPath(projectId, id),
        method: 'PATCH',
        data: { agent: data },
      }),
      invalidatesTags: [QueryTag.Agents],
    }),

    // Delete agent
    deleteCompanyAgent: builder.mutation<void, number>({
      query: (id) => ({
        url: Routes.backend.apiV1CompanyAgentPath(id),
        method: 'DELETE',
      }),
      invalidatesTags: [QueryTag.Agents],
    }),

    deleteProjectAgent: builder.mutation<void, { projectId: number; id: number }>({
      query: ({ projectId, id }) => ({
        url: Routes.backend.apiV1CompanyProjectAgentPath(projectId, id),
        method: 'DELETE',
      }),
      invalidatesTags: [QueryTag.Agents],
    }),
  }),
});

export const {
  useGetCompanyAgentsQuery,
  useGetProjectAgentsQuery,
  useCreateCompanyAgentMutation,
  useCreateProjectAgentMutation,
  useUpdateCompanyAgentMutation,
  useUpdateProjectAgentMutation,
  useDeleteCompanyAgentMutation,
  useDeleteProjectAgentMutation,
} = agentsApi;
