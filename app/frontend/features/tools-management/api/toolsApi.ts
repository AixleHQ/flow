import { baseApi, QueryTag } from 'shared/api';
import { Routes } from 'shared/routes';

import type { Tool, CreateToolRequest, UpdateToolRequest } from '../lib/types';

interface ToolsResponse {
  items: Tool[];
}

type CreateToolArg = CreateToolRequest | { formData: FormData };
type CreateProjectToolArg = { projectId: number } & (CreateToolRequest | { formData: FormData });
type UpdateToolArg = UpdateToolRequest | { id: number; formData: FormData };
type UpdateProjectToolArg = { projectId: number } & (UpdateToolRequest | { id: number; formData: FormData });

const isFormDataArg = (arg: Record<string, unknown>): arg is { formData: FormData } => {
  return 'formData' in arg && arg.formData instanceof FormData;
};

export const toolsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
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

    createCompanyTool: builder.mutation<Tool, CreateToolArg>({
      query: (arg) => {
        if (isFormDataArg(arg as Record<string, unknown>)) {
          return {
            url: Routes.backend.apiV1CompanyToolsPath(),
            method: 'POST',
            data: (arg as { formData: FormData }).formData,
            headers: { 'Content-Type': 'multipart/form-data' },
          };
        }
        return {
          url: Routes.backend.apiV1CompanyToolsPath(),
          method: 'POST',
          data: { tool: arg },
        };
      },
      invalidatesTags: [QueryTag.Tools],
    }),

    createProjectTool: builder.mutation<Tool, CreateProjectToolArg>({
      query: (arg) => {
        const { projectId, ...rest } = arg;
        if (isFormDataArg(rest as Record<string, unknown>)) {
          return {
            url: Routes.backend.apiV1CompanyProjectToolsPath(projectId),
            method: 'POST',
            data: (rest as { formData: FormData }).formData,
            headers: { 'Content-Type': 'multipart/form-data' },
          };
        }
        return {
          url: Routes.backend.apiV1CompanyProjectToolsPath(projectId),
          method: 'POST',
          data: { tool: rest },
        };
      },
      invalidatesTags: [QueryTag.Tools],
    }),

    updateCompanyTool: builder.mutation<Tool, UpdateToolArg>({
      query: (arg) => {
        if (isFormDataArg(arg as Record<string, unknown>)) {
          const { id, formData } = arg as { id: number; formData: FormData };
          return {
            url: Routes.backend.apiV1CompanyToolPath(id),
            method: 'PATCH',
            data: formData,
            headers: { 'Content-Type': 'multipart/form-data' },
          };
        }
        const { id, ...data } = arg as UpdateToolRequest;
        return {
          url: Routes.backend.apiV1CompanyToolPath(id),
          method: 'PATCH',
          data: { tool: data },
        };
      },
      invalidatesTags: [QueryTag.Tools],
    }),

    updateProjectTool: builder.mutation<Tool, UpdateProjectToolArg>({
      query: (arg) => {
        const { projectId, ...rest } = arg;
        if (isFormDataArg(rest as Record<string, unknown>)) {
          const { id, formData } = rest as { id: number; formData: FormData };
          return {
            url: Routes.backend.apiV1CompanyProjectToolPath(projectId, id),
            method: 'PATCH',
            data: formData,
            headers: { 'Content-Type': 'multipart/form-data' },
          };
        }
        const { id, ...data } = rest as UpdateToolRequest;
        return {
          url: Routes.backend.apiV1CompanyProjectToolPath(projectId, id),
          method: 'PATCH',
          data: { tool: data },
        };
      },
      invalidatesTags: [QueryTag.Tools],
    }),

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
