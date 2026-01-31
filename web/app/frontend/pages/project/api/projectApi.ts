import type { IArtifact } from 'entities/artifact';
import type { IProject } from 'entities/project';
import type { ApiResponse, ApiCollectionResponse } from 'shared/api';
import { baseApi, QueryTag } from 'shared/api';
import { Routes } from 'shared/routes';

import type { IWorkflow, IWorkflowRun, ITask } from '../lib/types';

export const projectApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    project: builder.query<ApiResponse<IProject>, string>({
      query: (projectId) => ({ url: Routes.backend.apiV1CompanyProjectPath(projectId) }),
      providesTags: (_result, _error, projectId) => [{ type: QueryTag.Project, id: projectId }],
    }),

    projectWorkflows: builder.query<ApiCollectionResponse<IWorkflow>, string>({
      query: (projectId) => ({ url: `/projects/${projectId}/workflows` }),
      providesTags: (result) =>
        result?.items
          ? [
              { type: QueryTag.Workflow, id: 'LIST' },
              ...result.items.map(({ id }) => ({ type: QueryTag.Workflow, id })),
            ]
          : [{ type: QueryTag.Workflow, id: 'LIST' }],
    }),

    projectWorkflowRuns: builder.query<ApiCollectionResponse<IWorkflowRun>, string>({
      query: (projectId) => ({ url: `/projects/${projectId}/workflow_runs` }),
      providesTags: (result) =>
        result?.items
          ? [
              { type: QueryTag.WorkflowRun, id: 'LIST' },
              ...result.items.map(({ id }) => ({ type: QueryTag.WorkflowRun, id })),
            ]
          : [{ type: QueryTag.WorkflowRun, id: 'LIST' }],
    }),

    projectArtifacts: builder.query<ApiCollectionResponse<IArtifact>, string>({
      query: (projectId) => ({ url: `/projects/${projectId}/artifacts` }),
      providesTags: (result) =>
        result?.items
          ? [
              { type: QueryTag.Artifact, id: 'LIST' },
              ...result.items.map(({ id }) => ({ type: QueryTag.Artifact, id })),
            ]
          : [{ type: QueryTag.Artifact, id: 'LIST' }],
    }),

    projectTasks: builder.query<ApiCollectionResponse<ITask>, string>({
      query: (projectId) => ({ url: `/projects/${projectId}/tasks` }),
      providesTags: (result) =>
        result?.items
          ? [{ type: QueryTag.Task, id: 'LIST' }, ...result.items.map(({ id }) => ({ type: QueryTag.Task, id }))]
          : [{ type: QueryTag.Task, id: 'LIST' }],
    }),
  }),
});

export const {
  useProjectQuery,
  useProjectWorkflowsQuery,
  useProjectWorkflowRunsQuery,
  useProjectArtifactsQuery,
  useProjectTasksQuery,
} = projectApi;
