import type { ITerminalSession } from 'entities/terminal-session';
import { baseApi, QueryTag, type ApiResponse, type ApiCollectionResponse } from 'shared/api';
import { Routes } from 'shared/routes';

interface StartAixleBuilderRequest {
  projectId: number;
  agentRuntime?: string;
  preferredModel?: string;
  inputAssetIds?: number[];
}

export const aixleBuilderApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    startAixleBuilder: builder.mutation<ITerminalSession, StartAixleBuilderRequest>({
      query: ({ projectId, agentRuntime, preferredModel, inputAssetIds }) => ({
        url: Routes.backend.startApiV1CompanyProjectAixleBuilderPath(projectId),
        method: 'POST',
        data: { agentRuntime, preferredModel, inputAssetIds },
      }),
      transformResponse: (response: ApiResponse<ITerminalSession>) => response.data,
      invalidatesTags: [QueryTag.TerminalSession],
    }),

    getAixleBuilderSessions: builder.query<ITerminalSession[], number>({
      query: (projectId) => ({
        url: Routes.backend.statusApiV1CompanyProjectAixleBuilderPath(projectId),
        method: 'GET',
      }),
      transformResponse: (response: ApiCollectionResponse<ITerminalSession>) => response.items,
      providesTags: [QueryTag.TerminalSession],
    }),
  }),
});

export const { useStartAixleBuilderMutation, useGetAixleBuilderSessionsQuery } = aixleBuilderApi;
