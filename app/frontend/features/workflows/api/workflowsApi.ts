import { baseApi, QueryTag } from 'shared/api';
import { Routes } from 'shared/routes';

import type { Workflow, CreateWorkflowRequest, UpdateWorkflowRequest } from '../lib/types';

interface WorkflowsResponse {
  items: Workflow[];
}

export const workflowsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getCompanyWorkflows: builder.query<Workflow[], void>({
      query: () => ({
        url: Routes.backend.apiV1CompanyWorkflowsPath(),
        method: 'GET',
      }),
      transformResponse: (response: Workflow[] | WorkflowsResponse) => {
        return Array.isArray(response) ? response : response.items;
      },
      providesTags: [QueryTag.Workflow],
    }),

    getProjectWorkflows: builder.query<Workflow[], number>({
      query: (projectId) => ({
        url: Routes.backend.apiV1CompanyProjectWorkflowsPath(projectId),
        method: 'GET',
      }),
      transformResponse: (response: Workflow[] | WorkflowsResponse) => {
        return Array.isArray(response) ? response : response.items;
      },
      providesTags: [QueryTag.Workflow],
    }),

    getCompanyWorkflow: builder.query<Workflow, number>({
      query: (id) => ({
        url: Routes.backend.apiV1CompanyWorkflowPath(id),
        method: 'GET',
      }),
      transformResponse: (response: { data: Workflow } | Workflow) => {
        return 'data' in response ? response.data : response;
      },
      providesTags: [QueryTag.Workflow],
    }),

    getWorkflow: builder.query<Workflow, { projectId: number; id: number }>({
      query: ({ projectId, id }) => ({
        url: Routes.backend.apiV1CompanyProjectWorkflowPath(projectId, id),
        method: 'GET',
      }),
      transformResponse: (response: { data: Workflow } | Workflow) => {
        return 'data' in response ? response.data : response;
      },
      providesTags: [QueryTag.Workflow],
    }),

    createCompanyWorkflow: builder.mutation<Workflow, CreateWorkflowRequest>({
      query: (data) => ({
        url: Routes.backend.apiV1CompanyWorkflowsPath(),
        method: 'POST',
        data: { workflow: data },
      }),
      transformResponse: (response: { workflow: Workflow } | Workflow) => {
        return 'workflow' in response ? response.workflow : response;
      },
      invalidatesTags: [QueryTag.Workflow],
    }),

    createProjectWorkflow: builder.mutation<Workflow, { projectId: number } & CreateWorkflowRequest>({
      query: ({ projectId, ...data }) => ({
        url: Routes.backend.apiV1CompanyProjectWorkflowsPath(projectId),
        method: 'POST',
        data: { workflow: data },
      }),
      transformResponse: (response: { workflow: Workflow } | Workflow) => {
        return 'workflow' in response ? response.workflow : response;
      },
      invalidatesTags: [QueryTag.Workflow],
    }),

    updateCompanyWorkflow: builder.mutation<Workflow, UpdateWorkflowRequest>({
      query: ({ id, ...data }) => ({
        url: Routes.backend.apiV1CompanyWorkflowPath(id),
        method: 'PATCH',
        data: { workflow: data },
      }),
      invalidatesTags: [QueryTag.Workflow],
    }),

    updateProjectWorkflow: builder.mutation<Workflow, { projectId: number } & UpdateWorkflowRequest>({
      query: ({ projectId, id, ...data }) => ({
        url: Routes.backend.apiV1CompanyProjectWorkflowPath(projectId, id),
        method: 'PATCH',
        data: { workflow: data },
      }),
      invalidatesTags: [QueryTag.Workflow],
    }),

    deleteCompanyWorkflow: builder.mutation<void, number>({
      query: (id) => ({
        url: Routes.backend.apiV1CompanyWorkflowPath(id),
        method: 'DELETE',
      }),
      invalidatesTags: [QueryTag.Workflow],
    }),

    deleteProjectWorkflow: builder.mutation<void, { projectId: number; id: number }>({
      query: ({ projectId, id }) => ({
        url: Routes.backend.apiV1CompanyProjectWorkflowPath(projectId, id),
        method: 'DELETE',
      }),
      invalidatesTags: [QueryTag.Workflow],
    }),

    duplicateWorkflowToProject: builder.mutation<Workflow, { projectId: number; id: number }>({
      query: ({ projectId, id }) => ({
        url: Routes.backend.duplicateApiV1CompanyProjectWorkflowPath(projectId, id),
        method: 'POST',
      }),
      transformResponse: (response: { workflow: Workflow } | Workflow) => {
        return 'workflow' in response ? response.workflow : response;
      },
      invalidatesTags: [QueryTag.Workflow],
    }),
  }),
});

export const {
  useGetCompanyWorkflowsQuery,
  useGetCompanyWorkflowQuery,
  useGetProjectWorkflowsQuery,
  useGetWorkflowQuery,
  useCreateCompanyWorkflowMutation,
  useCreateProjectWorkflowMutation,
  useUpdateCompanyWorkflowMutation,
  useUpdateProjectWorkflowMutation,
  useDeleteCompanyWorkflowMutation,
  useDeleteProjectWorkflowMutation,
  useDuplicateWorkflowToProjectMutation,
} = workflowsApi;
