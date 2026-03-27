import { baseApi, QueryTag, type ApiResponse, type ApiCollectionResponse } from 'shared/api';
import { Routes } from 'shared/routes';

interface WorkflowRunSummary {
  id: number;
  state: string;
  mode: string;
  agentRuntime: string | null;
  startedAt: string | null;
  completedAt: string | null;
  createdAt: string;
  workflowId: number;
  projectId: number;
}

interface StartPaladBuilderRequest {
  projectId: number;
  agentRuntime?: string;
}

interface StartPaladBuilderResponse {
  id: number;
  state: string;
  workflowId: number;
  projectId: number;
}

export const paladBuilderApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    startPaladBuilder: builder.mutation<StartPaladBuilderResponse, StartPaladBuilderRequest>({
      query: ({ projectId, agentRuntime }) => ({
        url: Routes.backend.startApiV1CompanyProjectPaladBuilderPath(projectId),
        method: 'POST',
        data: { agentRuntime },
      }),
      transformResponse: (response: ApiResponse<StartPaladBuilderResponse>) => response.data,
      invalidatesTags: [QueryTag.WorkflowRun],
    }),

    getPaladBuilderStatus: builder.query<WorkflowRunSummary[], number>({
      query: (projectId) => ({
        url: Routes.backend.statusApiV1CompanyProjectPaladBuilderPath(projectId),
        method: 'GET',
      }),
      transformResponse: (response: ApiCollectionResponse<WorkflowRunSummary>) => response.items,
      providesTags: [QueryTag.WorkflowRun],
    }),
  }),
});

export const { useStartPaladBuilderMutation, useGetPaladBuilderStatusQuery } = paladBuilderApi;
