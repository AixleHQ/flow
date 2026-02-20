import { baseApi, QueryTag } from 'shared/api';
import { Routes } from 'shared/routes';

interface ConfigItem {
  id: number;
  name: string;
  value: string;
}

interface ConfigItemsResponse {
  items: ConfigItem[];
}

export const sharedConfigItemsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    // Company-level config items (for selection in other forms)
    getCompanyConfigItemsForSelect: builder.query<ConfigItem[], void>({
      query: () => ({
        url: Routes.backend.apiV1CompanyConfigItemsPath(),
        method: 'GET',
      }),
      transformResponse: (response: ConfigItem[] | ConfigItemsResponse) => {
        return Array.isArray(response) ? response : response.items;
      },
      providesTags: [QueryTag.ConfigItems],
    }),

    // Project-level config items (for selection in other forms)
    getProjectConfigItemsForSelect: builder.query<ConfigItem[], number>({
      query: (projectId) => ({
        url: Routes.backend.apiV1CompanyProjectConfigItemsPath(projectId),
        method: 'GET',
      }),
      transformResponse: (response: ConfigItem[] | ConfigItemsResponse) => {
        return Array.isArray(response) ? response : response.items;
      },
      providesTags: [QueryTag.ConfigItems],
    }),
  }),
});

export const { useGetCompanyConfigItemsForSelectQuery, useGetProjectConfigItemsForSelectQuery } = sharedConfigItemsApi;
