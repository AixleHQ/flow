import type {
  ICreateTerminalSessionRequest,
  ICreateTerminalSessionResponse,
  IFinishAuthResponse,
  IGetTerminalSessionResponse,
  IListTerminalSessionsParams,
  IListTerminalSessionsResponse,
  IReviewArtifactsRequest,
  ISessionArtifact,
  ITerminalSession,
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

    // List terminal sessions — routes to company or project endpoint based on projectId
    listTerminalSessions: builder.query<IListTerminalSessionsResponse, IListTerminalSessionsParams | void>({
      query: (params) => {
        const baseUrl = params?.projectId
          ? Routes.backend.apiV1CompanyProjectTerminalSessionsPath(params.projectId)
          : Routes.backend.apiV1CompanyTerminalSessionsPath();

        const searchParams = new URLSearchParams();
        if (params?.sessionType) searchParams.set('q[session_type_eq]', params.sessionType);
        if (params?.agentType) searchParams.set('q[agent_type_eq]', params.agentType);
        if (params?.state) searchParams.set('q[state_eq]', params.state);
        if (params?.createdAfter) searchParams.set('q[created_at_gteq]', params.createdAfter);
        if (params?.createdBefore) searchParams.set('q[created_at_lteq]', params.createdBefore);
        if (params?.page) searchParams.set('page', String(params.page));
        if (params?.perPage) searchParams.set('per_page', String(params.perPage));
        const qs = searchParams.toString();
        return {
          url: `${baseUrl}${qs ? `?${qs}` : ''}`,
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

    // Gracefully finish session (stop → collect assets → collect usage)
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

    // Get pending artifacts for a session
    getSessionArtifacts: builder.query<ISessionArtifact[], number>({
      query: (sessionId) => ({
        url: `/api/v1/company/terminal_sessions/${sessionId}/artifacts`,
        method: 'GET',
      }),
      transformResponse: (response: { items?: ISessionArtifact[]; data?: ISessionArtifact[] }) =>
        response.items ?? response.data ?? (response as unknown as ISessionArtifact[]),
      providesTags: (_result, _error, sessionId) => [{ type: QueryTag.TerminalSession, id: `artifacts-${sessionId}` }],
    }),

    // Review session artifacts (save/dismiss decisions)
    reviewSessionArtifacts: builder.mutation<{ data: ITerminalSession }, IReviewArtifactsRequest>({
      query: ({ sessionId, ...body }) => ({
        url: `/api/v1/company/terminal_sessions/${sessionId}/artifacts/review`,
        method: 'POST',
        data: body,
      }),
      invalidatesTags: (_result, _error, { sessionId }) => [
        { type: QueryTag.TerminalSession, id: sessionId },
        { type: QueryTag.TerminalSession, id: `artifacts-${sessionId}` },
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
  useGetSessionArtifactsQuery,
  useReviewSessionArtifactsMutation,
} = terminalSessionApi;
