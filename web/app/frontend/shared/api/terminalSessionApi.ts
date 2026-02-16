import type {
  ICreateTerminalSessionRequest,
  ICreateTerminalSessionResponse,
  IFinishAuthResponse,
  IGetTerminalSessionResponse,
  IListTerminalSessionsParams,
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

    // List terminal sessions with optional ransack filters and pagination
    listTerminalSessions: builder.query<IListTerminalSessionsResponse, IListTerminalSessionsParams | void>({
      query: (params) => {
        const searchParams = new URLSearchParams();
        if (params?.projectId) searchParams.set('q[project_id_eq]', String(params.projectId));
        if (params?.sessionType) searchParams.set('q[session_type_eq]', params.sessionType);
        if (params?.state) searchParams.set('q[state_eq]', params.state);
        if (params?.page) searchParams.set('page', String(params.page));
        if (params?.perPage) searchParams.set('per_page', String(params.perPage));
        const qs = searchParams.toString();
        return {
          url: `${Routes.backend.apiV1TerminalSessionsPath()}${qs ? `?${qs}` : ''}`,
          method: 'GET',
        };
      },
      providesTags: (result) =>
        result
          ? [
              ...result.items.map(({ id }) => ({ type: QueryTag.TerminalSession, id })),
              { type: QueryTag.TerminalSession, id: 'LIST' },
            ]
          : [{ type: QueryTag.TerminalSession, id: 'LIST' }],
    }),

    // Gracefully finish session (stop → collect artifacts → collect usage)
    finishSession: builder.mutation<IFinishAuthResponse, { sessionId: number }>({
      query: ({ sessionId }) => ({
        url: Routes.backend.finishApiV1TerminalSessionPath(sessionId),
        method: 'POST',
      }),
      invalidatesTags: (_result, _error, { sessionId }) => [{ type: QueryTag.TerminalSession, id: sessionId }],
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
  useFinishSessionMutation,
  useDeleteTerminalSessionMutation,
} = terminalSessionApi;
