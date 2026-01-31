import type {
  ICancelSessionResponse,
  ICreateTerminalSessionRequest,
  ICreateTerminalSessionResponse,
  IFinishAuthResponse,
  IGetTerminalSessionResponse,
  IListTerminalSessionsResponse,
} from 'entities/terminal-session';

import { Routes } from '../routes';

import { baseApi } from './baseApi';
import { QueryTag } from './QueryTag';

export const terminalSessionApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    // Create new terminal session (start authentication)
    createTerminalSession: builder.mutation<ICreateTerminalSessionResponse, ICreateTerminalSessionRequest>({
      query: (body) => ({
        url: Routes.backend.apiV1TerminalSessionsPath(),
        method: 'POST',
        data: body,
      }),
      invalidatesTags: [QueryTag.TerminalSession],
    }),

    // Get single terminal session by ID or route_token
    getTerminalSession: builder.query<IGetTerminalSessionResponse, number | string>({
      query: (idOrToken) => ({
        url: Routes.backend.apiV1TerminalSessionPath(idOrToken),
        method: 'GET',
      }),
      providesTags: (result) => (result ? [{ type: QueryTag.TerminalSession, id: result.data.id }] : []),
    }),

    // List all terminal sessions for current user
    listTerminalSessions: builder.query<IListTerminalSessionsResponse, void>({
      query: () => ({
        url: Routes.backend.apiV1TerminalSessionsPath(),
        method: 'GET',
      }),
      providesTags: (result) =>
        result
          ? [
              ...result.items.map(({ id }) => ({ type: QueryTag.TerminalSession, id })),
              { type: QueryTag.TerminalSession, id: 'LIST' },
            ]
          : [{ type: QueryTag.TerminalSession, id: 'LIST' }],
    }),

    // Finish authentication (user clicked "Finish" button)
    finishAuth: builder.mutation<IFinishAuthResponse, { sessionId: number }>({
      query: ({ sessionId }) => ({
        url: Routes.backend.finishAuthApiV1TerminalSessionPath(sessionId),
        method: 'POST',
      }),
      invalidatesTags: (_result, _error, { sessionId }) => [{ type: QueryTag.TerminalSession, id: sessionId }],
    }),

    // Cancel active session
    cancelSession: builder.mutation<ICancelSessionResponse, number>({
      query: (id) => ({
        url: Routes.backend.cancelApiV1TerminalSessionPath(id),
        method: 'POST',
      }),
      invalidatesTags: (_result, _error, id) => [{ type: QueryTag.TerminalSession, id }],
    }),

    // Delete terminal session
    deleteTerminalSession: builder.mutation<void, number>({
      query: (id) => ({
        url: Routes.backend.apiV1TerminalSessionPath(id),
        method: 'DELETE',
      }),
      invalidatesTags: (_result, _error, id) => [
        { type: QueryTag.TerminalSession, id },
        { type: QueryTag.TerminalSession, id: 'LIST' },
      ],
    }),
  }),
});

export const {
  useCreateTerminalSessionMutation,
  useGetTerminalSessionQuery,
  useListTerminalSessionsQuery,
  useFinishAuthMutation,
  useCancelSessionMutation,
  useDeleteTerminalSessionMutation,
} = terminalSessionApi;
