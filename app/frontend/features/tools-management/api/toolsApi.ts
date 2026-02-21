import { baseApi, QueryTag } from 'shared/api';
import { Routes } from 'shared/routes';

import type { Tool, CreateToolRequest, UpdateToolRequest } from '../lib/types';

interface ToolsResponse {
  items: Tool[];
}

export const toolsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    // Company-level tools (internal + company)
    getCompanyTools: builder.query<Tool[], void>({
      query: () => ({
        url: Routes.backend.apiV1CompanyToolsPath(),
        method: 'GET',
      }),
      transformResponse: (response: Tool[] | ToolsResponse) => {
        return Array.isArray(response) ? response : response.items;
      },
      providesTags: [QueryTag.Tools],
    }),

    // Project-level tools (merged list)
    getProjectTools: builder.query<Tool[], number>({
      query: (projectId) => ({
        url: Routes.backend.apiV1CompanyProjectToolsPath(projectId),
        method: 'GET',
      }),
      transformResponse: (response: Tool[] | ToolsResponse) => {
        return Array.isArray(response) ? response : response.items;
      },
      providesTags: [QueryTag.Tools],
    }),

    // Create tool
    createCompanyTool: builder.mutation<Tool, CreateToolRequest>({
      query: (data) => ({
        url: Routes.backend.apiV1CompanyToolsPath(),
        method: 'POST',
        data: { tool: data },
      }),
      invalidatesTags: [QueryTag.Tools],
    }),

    createProjectTool: builder.mutation<Tool, { projectId: number } & CreateToolRequest>({
      query: ({ projectId, ...data }) => ({
        url: Routes.backend.apiV1CompanyProjectToolsPath(projectId),
        method: 'POST',
        data: { tool: data },
      }),
      invalidatesTags: [QueryTag.Tools],
    }),

    // Update tool
    updateCompanyTool: builder.mutation<Tool, UpdateToolRequest>({
      query: ({ id, ...data }) => ({
        url: Routes.backend.apiV1CompanyToolPath(id),
        method: 'PATCH',
        data: { tool: data },
      }),
      invalidatesTags: [QueryTag.Tools],
    }),

    updateProjectTool: builder.mutation<Tool, { projectId: number } & UpdateToolRequest>({
      query: ({ projectId, id, ...data }) => ({
        url: Routes.backend.apiV1CompanyProjectToolPath(projectId, id),
        method: 'PATCH',
        data: { tool: data },
      }),
      invalidatesTags: [QueryTag.Tools],
    }),

    // Delete tool
    deleteCompanyTool: builder.mutation<void, number>({
      query: (id) => ({
        url: Routes.backend.apiV1CompanyToolPath(id),
        method: 'DELETE',
      }),
      invalidatesTags: [QueryTag.Tools],
    }),

    deleteProjectTool: builder.mutation<void, { projectId: number; id: number }>({
      query: ({ projectId, id }) => ({
        url: Routes.backend.apiV1CompanyProjectToolPath(projectId, id),
        method: 'DELETE',
      }),
      invalidatesTags: [QueryTag.Tools],
    }),
  }),
});

export const {
  useGetCompanyToolsQuery,
  useGetProjectToolsQuery,
  useCreateCompanyToolMutation,
  useCreateProjectToolMutation,
  useUpdateCompanyToolMutation,
  useUpdateProjectToolMutation,
  useDeleteCompanyToolMutation,
  useDeleteProjectToolMutation,
} = toolsApi;
