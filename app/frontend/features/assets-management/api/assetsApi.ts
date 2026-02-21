import { baseApi, QueryTag } from 'shared/api';
import { Routes } from 'shared/routes';

import type { Asset, CreateAssetPayload, DetailedAssetVersion, UpdateAssetRequest } from '../lib/types';

export const assetsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getCompanyAssets: builder.query<Asset[], void>({
      query: () => ({
        url: Routes.backend.apiV1CompanyAssetsPath(),
        method: 'GET',
      }),
      transformResponse: (response: Asset[] | { items: Asset[] }) =>
        Array.isArray(response) ? response : response.items,
      providesTags: [QueryTag.Assets],
    }),

    getProjectAssets: builder.query<Asset[], number>({
      query: (projectId) => ({
        url: Routes.backend.apiV1CompanyProjectAssetsPath(projectId),
        method: 'GET',
      }),
      transformResponse: (response: Asset[] | { items: Asset[] }) =>
        Array.isArray(response) ? response : response.items,
      providesTags: [QueryTag.Assets],
    }),

    createCompanyAsset: builder.mutation<Asset, CreateAssetPayload>({
      query: (payload) => ({
        url: Routes.backend.apiV1CompanyAssetsPath(),
        method: 'POST',
        data: {
          asset: {
            name: payload.name,
            folder: payload.folder,
            tags: payload.tags,
            file: payload.file,
          },
        },
      }),
      invalidatesTags: [QueryTag.Assets],
    }),

    createProjectAsset: builder.mutation<Asset, { projectId: number } & CreateAssetPayload>({
      query: ({ projectId, ...payload }) => ({
        url: Routes.backend.apiV1CompanyProjectAssetsPath(projectId),
        method: 'POST',
        data: {
          asset: {
            name: payload.name,
            folder: payload.folder,
            tags: payload.tags,
            file: payload.file,
          },
        },
      }),
      invalidatesTags: [QueryTag.Assets],
    }),

    updateCompanyAsset: builder.mutation<Asset, UpdateAssetRequest>({
      query: ({ id, ...data }) => ({
        url: Routes.backend.apiV1CompanyAssetPath(id),
        method: 'PATCH',
        data: { asset: data },
      }),
      invalidatesTags: [QueryTag.Assets],
    }),

    updateProjectAsset: builder.mutation<Asset, { projectId: number } & UpdateAssetRequest>({
      query: ({ projectId, id, ...data }) => ({
        url: Routes.backend.apiV1CompanyProjectAssetPath(projectId, id),
        method: 'PATCH',
        data: { asset: data },
      }),
      invalidatesTags: [QueryTag.Assets],
    }),

    deleteCompanyAsset: builder.mutation<void, number>({
      query: (id) => ({
        url: Routes.backend.apiV1CompanyAssetPath(id),
        method: 'DELETE',
      }),
      invalidatesTags: [QueryTag.Assets],
    }),

    deleteProjectAsset: builder.mutation<void, { projectId: number; id: number }>({
      query: ({ projectId, id }) => ({
        url: Routes.backend.apiV1CompanyProjectAssetPath(projectId, id),
        method: 'DELETE',
      }),
      invalidatesTags: [QueryTag.Assets],
    }),

    restoreCompanyAsset: builder.mutation<Asset, number>({
      query: (id) => ({
        url: Routes.backend.restoreApiV1CompanyAssetPath(id),
        method: 'POST',
      }),
      invalidatesTags: [QueryTag.Assets],
    }),

    restoreProjectAsset: builder.mutation<Asset, { projectId: number; id: number }>({
      query: ({ projectId, id }) => ({
        url: Routes.backend.restoreApiV1CompanyProjectAssetPath(projectId, id),
        method: 'POST',
      }),
      invalidatesTags: [QueryTag.Assets],
    }),

    getCompanyAssetVersions: builder.query<DetailedAssetVersion[], number>({
      query: (assetId) => ({
        url: Routes.backend.versionsApiV1CompanyAssetPath(assetId),
        method: 'GET',
      }),
      transformResponse: (response: DetailedAssetVersion[] | { items: DetailedAssetVersion[] }) =>
        Array.isArray(response) ? response : response.items,
    }),

    getProjectAssetVersions: builder.query<DetailedAssetVersion[], { projectId: number; assetId: number }>({
      query: ({ projectId, assetId }) => ({
        url: Routes.backend.versionsApiV1CompanyProjectAssetPath(projectId, assetId),
        method: 'GET',
      }),
      transformResponse: (response: DetailedAssetVersion[] | { items: DetailedAssetVersion[] }) =>
        Array.isArray(response) ? response : response.items,
    }),
  }),
});

export const {
  useGetCompanyAssetsQuery,
  useGetProjectAssetsQuery,
  useCreateCompanyAssetMutation,
  useCreateProjectAssetMutation,
  useUpdateCompanyAssetMutation,
  useUpdateProjectAssetMutation,
  useDeleteCompanyAssetMutation,
  useDeleteProjectAssetMutation,
  useRestoreCompanyAssetMutation,
  useRestoreProjectAssetMutation,
  useGetCompanyAssetVersionsQuery,
  useGetProjectAssetVersionsQuery,
} = assetsApi;
