import type {
  ICancelSessionResponse,
  ICreateTerminalSessionRequest,
  ICreateTerminalSessionResponse,
  IFinishAuthResponse,
  IGetTerminalSessionResponse,
  IListTerminalSessionsResponse,
} from 'entities/terminal-session/model/types';

import { baseApi } from './baseApi';
import { QueryTag } from './QueryTag';

export const terminalSessionApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    // Create new terminal session (start authentication)
    createTerminalSession: builder.mutation<ICreateTerminalSessionResponse, ICreateTerminalSessionRequest>({
      query: (body) => ({
        url: '/api/v1/terminal_sessions',
        method: 'POST',
        data: body,
      }),
      invalidatesTags: [QueryTag.TerminalSession],
    }),

    // Get single terminal session by ID or route_token
    getTerminalSession: builder.query<IGetTerminalSessionResponse, number | string>({
      query: (idOrToken) => ({
        url: `/api/v1/terminal_sessions/${idOrToken}`,
        method: 'GET',
      }),
      providesTags: (result) =>
        result ? [{ type: QueryTag.TerminalSession, id: result.data.id }] : [],
    }),

    // List all terminal sessions for current user
    listTerminalSessions: builder.query<IListTerminalSessionsResponse, void>({
      query: () => ({
        url: '/api/v1/terminal_sessions',
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
        url: `/api/v1/terminal_sessions/${sessionId}/finish_auth`,
        method: 'POST',
      }),
      invalidatesTags: (result, error, { sessionId }) => [{ type: QueryTag.TerminalSession, id: sessionId }],
    }),

    // Cancel active session
    cancelSession: builder.mutation<ICancelSessionResponse, number>({
      query: (id) => ({
        url: `/api/v1/terminal_sessions/${id}/cancel`,
        method: 'POST',
      }),
      invalidatesTags: (result, error, id) => [{ type: QueryTag.TerminalSession, id }],
    }),

    // Delete terminal session
    deleteTerminalSession: builder.mutation<void, number>({
      query: (id) => ({
        url: `/api/v1/terminal_sessions/${id}`,
        method: 'DELETE',
      }),
      invalidatesTags: (result, error, id) => [
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
