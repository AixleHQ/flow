import { baseApi } from './baseApi';
import { QueryTag } from './QueryTag';

export interface AgentModel {
  modelId: string;
  displayName: string;
  description: string;
}

export const agentModelsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getAgentModels: builder.query<AgentModel[], string>({
      query: (agentRuntime) => ({
        url: '/api/v1/agent_models',
        method: 'GET',
        params: { agent_runtime: agentRuntime },
      }),
    }),
    updateDefaultModel: builder.mutation<unknown, { agentCredentialId: number; defaultModel: string | null }>({
      query: ({ agentCredentialId, defaultModel }) => ({
        url: '/api/v1/agent_models/update_default',
        method: 'PUT',
        data: { agent_credential_id: agentCredentialId, default_model: defaultModel },
      }),
      invalidatesTags: [QueryTag.CurrentUser],
    }),
  }),
});

export const { useGetAgentModelsQuery, useLazyGetAgentModelsQuery, useUpdateDefaultModelMutation } = agentModelsApi;
