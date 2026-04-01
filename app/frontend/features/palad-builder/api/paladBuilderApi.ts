import type { ITerminalSession } from 'entities/terminal-session';
import { baseApi, QueryTag, type ApiResponse, type ApiCollectionResponse } from 'shared/api';
import { Routes } from 'shared/routes';

interface StartPaladBuilderRequest {
  projectId: number;
  agentRuntime?: string;
  preferredModel?: string;
  inputAssetIds?: number[];
}

export const paladBuilderApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    startPaladBuilder: builder.mutation<ITerminalSession, StartPaladBuilderRequest>({
      query: ({ projectId, agentRuntime, preferredModel, inputAssetIds }) => ({
        url: Routes.backend.startApiV1CompanyProjectPaladBuilderPath(projectId),
        method: 'POST',
        data: { agentRuntime, preferredModel, inputAssetIds },
      }),
      transformResponse: (response: ApiResponse<ITerminalSession>) => response.data,
      invalidatesTags: [QueryTag.TerminalSession],
    }),

    getPaladBuilderSessions: builder.query<ITerminalSession[], number>({
      query: (projectId) => ({
        url: Routes.backend.statusApiV1CompanyProjectPaladBuilderPath(projectId),
        method: 'GET',
      }),
      transformResponse: (response: ApiCollectionResponse<ITerminalSession>) => response.items,
      providesTags: [QueryTag.TerminalSession],
    }),
  }),
});

export const { useStartPaladBuilderMutation, useGetPaladBuilderSessionsQuery } = paladBuilderApi;
