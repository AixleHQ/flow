import { baseApi, QueryTag, type ApiResponse, type ApiCollectionResponse } from 'shared/api';
import { Routes } from 'shared/routes';

import type { Step, CreateStepRequest, UpdateStepRequest } from '../lib/types';

export const stepsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getSteps: builder.query<Step[], { projectId: number; workflowId: number }>({
      query: ({ projectId, workflowId }) => ({
        url: Routes.backend.apiV1CompanyProjectWorkflowStepsPath(projectId, workflowId),
        method: 'GET',
      }),
      transformResponse: (response: ApiCollectionResponse<Step>) => response.items,
      providesTags: [QueryTag.Workflow],
    }),

    getStep: builder.query<Step, { projectId: number; workflowId: number; id: number }>({
      query: ({ projectId, workflowId, id }) => ({
        url: Routes.backend.apiV1CompanyProjectWorkflowStepPath(projectId, workflowId, id),
        method: 'GET',
      }),
      transformResponse: (response: ApiResponse<Step>) => response.data,
      providesTags: [QueryTag.Workflow],
    }),

    createStep: builder.mutation<Step, { projectId: number; workflowId: number } & CreateStepRequest>({
      query: ({ projectId, workflowId, ...data }) => ({
        url: Routes.backend.apiV1CompanyProjectWorkflowStepsPath(projectId, workflowId),
        method: 'POST',
        data: { step: data },
      }),
      transformResponse: (response: ApiResponse<Step>) => response.data,
      invalidatesTags: [QueryTag.Workflow],
    }),

    updateStep: builder.mutation<Step, { projectId: number; workflowId: number } & UpdateStepRequest>({
      query: ({ projectId, workflowId, id, ...data }) => ({
        url: Routes.backend.apiV1CompanyProjectWorkflowStepPath(projectId, workflowId, id),
        method: 'PATCH',
        data: { step: data },
      }),
      invalidatesTags: [QueryTag.Workflow],
    }),

    deleteStep: builder.mutation<void, { projectId: number; workflowId: number; id: number }>({
      query: ({ projectId, workflowId, id }) => ({
        url: Routes.backend.apiV1CompanyProjectWorkflowStepPath(projectId, workflowId, id),
        method: 'DELETE',
      }),
      invalidatesTags: [QueryTag.Workflow],
    }),

    reorderSteps: builder.mutation<void, { projectId: number; workflowId: number; positions: Record<number, number> }>(
      {
        query: ({ projectId, workflowId, positions }) => ({
          url: Routes.backend.reorderApiV1CompanyProjectWorkflowStepsPath(projectId, workflowId),
          method: 'PATCH',
          data: { positions },
        }),
        invalidatesTags: [QueryTag.Workflow],
      },
    ),

    getCompanySteps: builder.query<Step[], { workflowId: number }>({
      query: ({ workflowId }) => ({
        url: Routes.backend.apiV1CompanyWorkflowStepsPath(workflowId),
        method: 'GET',
      }),
      transformResponse: (response: ApiCollectionResponse<Step>) => response.items,
      providesTags: [QueryTag.Workflow],
    }),

    createCompanyStep: builder.mutation<Step, { workflowId: number } & CreateStepRequest>({
      query: ({ workflowId, ...data }) => ({
        url: Routes.backend.apiV1CompanyWorkflowStepsPath(workflowId),
        method: 'POST',
        data: { step: data },
      }),
      transformResponse: (response: ApiResponse<Step>) => response.data,
      invalidatesTags: [QueryTag.Workflow],
    }),

    updateCompanyStep: builder.mutation<Step, { workflowId: number } & UpdateStepRequest>({
      query: ({ workflowId, id, ...data }) => ({
        url: Routes.backend.apiV1CompanyWorkflowStepPath(workflowId, id),
        method: 'PATCH',
        data: { step: data },
      }),
      invalidatesTags: [QueryTag.Workflow],
    }),

    deleteCompanyStep: builder.mutation<void, { workflowId: number; id: number }>({
      query: ({ workflowId, id }) => ({
        url: Routes.backend.apiV1CompanyWorkflowStepPath(workflowId, id),
        method: 'DELETE',
      }),
      invalidatesTags: [QueryTag.Workflow],
    }),

    reorderCompanySteps: builder.mutation<void, { workflowId: number; positions: Record<number, number> }>({
      query: ({ workflowId, positions }) => ({
        url: Routes.backend.reorderApiV1CompanyWorkflowStepsPath(workflowId),
        method: 'PATCH',
        data: { positions },
      }),
      invalidatesTags: [QueryTag.Workflow],
    }),
  }),
});

export const {
  useGetStepsQuery,
  useGetStepQuery,
  useCreateStepMutation,
  useUpdateStepMutation,
  useDeleteStepMutation,
  useReorderStepsMutation,
  useGetCompanyStepsQuery,
  useCreateCompanyStepMutation,
  useUpdateCompanyStepMutation,
  useDeleteCompanyStepMutation,
  useReorderCompanyStepsMutation,
} = stepsApi;
