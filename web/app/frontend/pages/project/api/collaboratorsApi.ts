import { baseApi, QueryTag, type ApiResponse, type PaginatedResponse } from 'shared/api';
import { Routes } from 'shared/routes';

export interface ProjectMember {
  id: number;
  email: string;
  name: string;
  role: string;
  state: string;
}

export interface AddCollaboratorRequest {
  projectId: number;
  userId: number;
}

export const collaboratorsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getProjectCollaborators: builder.query<{ items: ProjectMember[] }, number>({
      query: (projectId) => ({
        url: Routes.backend.apiV1CompanyProjectCollaboratorsPath(projectId),
        method: 'GET',
      }),
      providesTags: (_result, _error, projectId) => [{ type: QueryTag.ProjectCollaborators, id: projectId }],
    }),
    addCollaborator: builder.mutation<ApiResponse<ProjectMember>, AddCollaboratorRequest>({
      query: ({ projectId, userId }) => ({
        url: Routes.backend.apiV1CompanyProjectCollaboratorsPath(projectId),
        method: 'POST',
        data: { collaborator: { user_id: userId } },
      }),
      invalidatesTags: (_result, _error, { projectId }) => [{ type: QueryTag.ProjectCollaborators, id: projectId }],
    }),
    removeCollaborator: builder.mutation<void, { projectId: number; userId: number }>({
      query: ({ projectId, userId }) => ({
        url: Routes.backend.apiV1CompanyProjectCollaboratorPath(projectId, userId),
        method: 'DELETE',
      }),
      invalidatesTags: (_result, _error, { projectId }) => [{ type: QueryTag.ProjectCollaborators, id: projectId }],
    }),
    // For adding collaborators - get company users
    getCompanyUsersForProject: builder.query<PaginatedResponse<ProjectMember>, void>({
      query: () => ({
        url: Routes.backend.apiV1CompanyUsersPath(),
        method: 'GET',
      }),
    }),
  }),
});

export const {
  useGetProjectCollaboratorsQuery,
  useAddCollaboratorMutation,
  useRemoveCollaboratorMutation,
  useGetCompanyUsersForProjectQuery,
} = collaboratorsApi;
