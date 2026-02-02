import { baseApi, QueryTag } from 'shared/api';
import { Routes } from 'shared/routes';

import type { ConfigItem, CreateConfigItemRequest, UpdateConfigItemRequest } from '../lib/types';

interface ConfigItemsResponse {
  items: ConfigItem[];
}

export const configItemsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    // Company-level config items
    getCompanyConfigItems: builder.query<ConfigItem[], void>({
      query: () => ({
        url: Routes.backend.apiV1CompanyConfigItemsPath(),
        method: 'GET',
      }),
      transformResponse: (response: ConfigItem[] | ConfigItemsResponse) => {
        // Handle both array and object with items
        return Array.isArray(response) ? response : response.items;
      },
      providesTags: [QueryTag.ConfigItems],
    }),

    // Project-level config items (merged list)
    getProjectConfigItems: builder.query<ConfigItem[], number>({
      query: (projectId) => ({
        url: Routes.backend.apiV1CompanyProjectPath(projectId),
        method: 'GET',
      }),
      transformResponse: (response: ConfigItem[] | ConfigItemsResponse) => {
        return Array.isArray(response) ? response : response.items;
      },
      providesTags: [QueryTag.ConfigItems],
    }),

    // Create config item (company or project level)
    createCompanyConfigItem: builder.mutation<ConfigItem, CreateConfigItemRequest>({
      query: (data) => ({
        url: Routes.backend.apiV1CompanyConfigItemsPath(),
        method: 'POST',
        data: { configItem: data },
      }),
      invalidatesTags: [QueryTag.ConfigItems],
    }),

    createProjectConfigItem: builder.mutation<ConfigItem, { projectId: number } & CreateConfigItemRequest>({
      query: ({ projectId, ...data }) => ({
        url: Routes.backend.apiV1CompanyProjectPath(projectId),
        method: 'POST',
        data: { configItem: data },
      }),
      invalidatesTags: [QueryTag.ConfigItems],
    }),

    // Update config item
    updateCompanyConfigItem: builder.mutation<ConfigItem, UpdateConfigItemRequest>({
      query: ({ id, ...data }) => ({
        url: Routes.backend.apiV1CompanyConfigItemPath(id),
        method: 'PATCH',
        data: { configItem: data },
      }),
      invalidatesTags: [QueryTag.ConfigItems],
    }),

    updateProjectConfigItem: builder.mutation<ConfigItem, { projectId: number } & UpdateConfigItemRequest>({
      query: ({ projectId, id, ...data }) => ({
        url: Routes.backend.apiV1CompanyProjectConfigItemPath(projectId, id),
        method: 'PATCH',
        data: { configItem: data },
      }),
      invalidatesTags: [QueryTag.ConfigItems],
    }),

    // Delete config item
    deleteCompanyConfigItem: builder.mutation<void, number>({
      query: (id) => ({
        url: Routes.backend.apiV1CompanyConfigItemPath(id),
        method: 'DELETE',
      }),
      invalidatesTags: [QueryTag.ConfigItems],
    }),

    deleteProjectConfigItem: builder.mutation<void, { projectId: number; id: number }>({
      query: ({ projectId, id }) => ({
        url: Routes.backend.apiV1CompanyProjectConfigItemPath(projectId, id),
        method: 'DELETE',
      }),
      invalidatesTags: [QueryTag.ConfigItems],
    }),
  }),
});

export const {
  useGetCompanyConfigItemsQuery,
  useGetProjectConfigItemsQuery,
  useCreateCompanyConfigItemMutation,
  useCreateProjectConfigItemMutation,
  useUpdateCompanyConfigItemMutation,
  useUpdateProjectConfigItemMutation,
  useDeleteCompanyConfigItemMutation,
  useDeleteProjectConfigItemMutation,
} = configItemsApi;
