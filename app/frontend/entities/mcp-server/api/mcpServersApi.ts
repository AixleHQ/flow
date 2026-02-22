import { baseApi, QueryTag } from 'shared/api';
import { Routes } from 'shared/routes';

import type { McpServer, CreateMcpServerDto, UpdateMcpServerDto } from '../model/types';

export const mcpServersApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    // Company-level MCP servers
    getMcpServers: builder.query<McpServer[], void>({
      query: () => ({ url: Routes.backend.apiV1CompanyMCPServersPath() }),
      transformResponse: (response: { items: McpServer[] }) => response.items,
      providesTags: [QueryTag.McpServers],
    }),

    createMcpServer: builder.mutation<McpServer, CreateMcpServerDto>({
      query: (body) => ({
        url: Routes.backend.apiV1CompanyMCPServersPath(),
        method: 'POST',
        data: { mcpServer: body },
      }),
      transformResponse: (response: { data: McpServer }) => response.data,
      invalidatesTags: [QueryTag.McpServers],
    }),

    updateMcpServer: builder.mutation<McpServer, { id: number; body: UpdateMcpServerDto }>({
      query: ({ id, body }) => ({
        url: Routes.backend.apiV1CompanyMCPServerPath(id),
        method: 'PATCH',
        data: { mcpServer: body },
      }),
      transformResponse: (response: { data: McpServer }) => response.data,
      invalidatesTags: [QueryTag.McpServers],
    }),

    deleteMcpServer: builder.mutation<void, number>({
      query: (id) => ({
        url: Routes.backend.apiV1CompanyMCPServerPath(id),
        method: 'DELETE',
      }),
      invalidatesTags: [QueryTag.McpServers],
    }),

    // Project-level MCP servers
    getProjectMcpServers: builder.query<McpServer[], number>({
      query: (projectId) => ({ url: Routes.backend.apiV1CompanyProjectMCPServersPath(projectId) }),
      transformResponse: (response: { items: McpServer[] }) => response.items,
      providesTags: [QueryTag.McpServers],
    }),

    createProjectMcpServer: builder.mutation<McpServer, { projectId: number; body: CreateMcpServerDto }>({
      query: ({ projectId, body }) => ({
        url: Routes.backend.apiV1CompanyProjectMCPServersPath(projectId),
        method: 'POST',
        data: { mcpServer: body },
      }),
      transformResponse: (response: { data: McpServer }) => response.data,
      invalidatesTags: [QueryTag.McpServers],
    }),

    updateProjectMcpServer: builder.mutation<McpServer, { projectId: number; id: number; body: UpdateMcpServerDto }>({
      query: ({ projectId, id, body }) => ({
        url: Routes.backend.apiV1CompanyProjectMCPServerPath(projectId, id),
        method: 'PATCH',
        data: { mcpServer: body },
      }),
      transformResponse: (response: { data: McpServer }) => response.data,
      invalidatesTags: [QueryTag.McpServers],
    }),

    deleteProjectMcpServer: builder.mutation<void, { projectId: number; id: number }>({
      query: ({ projectId, id }) => ({
        url: Routes.backend.apiV1CompanyProjectMCPServerPath(projectId, id),
        method: 'DELETE',
      }),
      invalidatesTags: [QueryTag.McpServers],
    }),
  }),
});

export const {
  useGetMcpServersQuery,
  useCreateMcpServerMutation,
  useUpdateMcpServerMutation,
  useDeleteMcpServerMutation,
  useGetProjectMcpServersQuery,
  useCreateProjectMcpServerMutation,
  useUpdateProjectMcpServerMutation,
  useDeleteProjectMcpServerMutation,
} = mcpServersApi;
