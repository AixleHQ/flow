import { baseApi, QueryTag, type ApiResponse, type ApiCollectionResponse } from 'shared/api';
import { Routes } from 'shared/routes';

import type { WorkflowRun, WorkflowRunAsset, CreateWorkflowRunRequest, IGetWorkflowRunsParams } from '../lib/types';

export const workflowRunsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getWorkflowRuns: builder.query<ApiCollectionResponse<WorkflowRun>, IGetWorkflowRunsParams>({
      query: ({ projectId, state, page, perPage }) => {
        const searchParams = new URLSearchParams();
        if (state) searchParams.set('q[state_eq]', state);
        if (page) searchParams.set('page', String(page));
        if (perPage) searchParams.set('per_page', String(perPage));
        const qs = searchParams.toString();
        return {
          url: `${Routes.backend.apiV1CompanyProjectWorkflowRunsPath(projectId)}${qs ? `?${qs}` : ''}`,
          method: 'GET',
        };
      },
      providesTags: [QueryTag.Workflow],
    }),

    getWorkflowRun: builder.query<WorkflowRun, { projectId: number; runId: number }>({
      query: ({ projectId, runId }) => ({
        url: Routes.backend.apiV1CompanyProjectWorkflowRunPath(projectId, runId),
        method: 'GET',
      }),
      transformResponse: (response: ApiResponse<WorkflowRun>) => response.data,
      providesTags: [QueryTag.Workflow],
    }),

    createWorkflowRun: builder.mutation<WorkflowRun, { projectId: number } & CreateWorkflowRunRequest>({
      query: ({ projectId, ...data }) => ({
        url: Routes.backend.apiV1CompanyProjectWorkflowRunsPath(projectId),
        method: 'POST',
        data: { workflowRun: data },
      }),
      transformResponse: (response: ApiResponse<WorkflowRun>) => response.data,
      invalidatesTags: [QueryTag.Workflow],
    }),

    approveStep: builder.mutation<WorkflowRun, { projectId: number; runId: number }>({
      query: ({ projectId, runId }) => ({
        url: Routes.backend.approveStepApiV1CompanyProjectWorkflowRunPath(projectId, runId),
        method: 'POST',
      }),
      invalidatesTags: [QueryTag.Workflow],
    }),

    retryStep: builder.mutation<WorkflowRun, { projectId: number; runId: number }>({
      query: ({ projectId, runId }) => ({
        url: Routes.backend.retryStepApiV1CompanyProjectWorkflowRunPath(projectId, runId),
        method: 'POST',
      }),
      invalidatesTags: [QueryTag.Workflow],
    }),

    skipStep: builder.mutation<WorkflowRun, { projectId: number; runId: number; reason?: string }>({
      query: ({ projectId, runId, reason }) => ({
        url: Routes.backend.skipStepApiV1CompanyProjectWorkflowRunPath(projectId, runId),
        method: 'POST',
        data: reason ? { reason } : undefined,
      }),
      invalidatesTags: [QueryTag.Workflow],
    }),

    cancelWorkflowRun: builder.mutation<WorkflowRun, { projectId: number; runId: number }>({
      query: ({ projectId, runId }) => ({
        url: Routes.backend.cancelApiV1CompanyProjectWorkflowRunPath(projectId, runId),
        method: 'POST',
      }),
      invalidatesTags: [QueryTag.Workflow],
    }),

    getWorkflowRunAssets: builder.query<WorkflowRunAsset[], { projectId: number; runId: number }>({
      query: ({ projectId, runId }) => ({
        url: Routes.backend.apiV1CompanyProjectWorkflowRunAssetsPath(projectId, runId),
        method: 'GET',
      }),
      transformResponse: (response: ApiCollectionResponse<WorkflowRunAsset>) => response.items,
      providesTags: [QueryTag.Workflow],
    }),

    exportAsset: builder.mutation<
      unknown,
      { projectId: number; runId: number; assetId: number; folder?: string; tags?: string[] }
    >({
      query: ({ projectId, runId, assetId, ...data }) => ({
        url: Routes.backend.exportApiV1CompanyProjectWorkflowRunAssetPath(projectId, runId, assetId),
        method: 'POST',
        data,
      }),
      invalidatesTags: [QueryTag.Workflow],
    }),

    exportAllAssets: builder.mutation<{ exportedCount: number }, { projectId: number; runId: number; folder?: string }>(
      {
        query: ({ projectId, runId, ...data }) => ({
          url: Routes.backend.exportAllApiV1CompanyProjectWorkflowRunAssetsPath(projectId, runId),
          method: 'POST',
          data,
        }),
        invalidatesTags: [QueryTag.Workflow],
      },
    ),
  }),
});

export const {
  useGetWorkflowRunsQuery,
  useGetWorkflowRunQuery,
  useCreateWorkflowRunMutation,
  useApproveStepMutation,
  useRetryStepMutation,
  useSkipStepMutation,
  useCancelWorkflowRunMutation,
  useGetWorkflowRunAssetsQuery,
  useExportAssetMutation,
  useExportAllAssetsMutation,
} = workflowRunsApi;
