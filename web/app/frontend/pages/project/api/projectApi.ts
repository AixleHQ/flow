import type { IArtifact } from 'entities/artifact';
import type { IProject } from 'entities/project';
import type { ApiResponse, ApiCollectionResponse } from 'shared/api';
import { baseApi, QueryTag, providesListTag } from 'shared/api';

import type { IWorkflow, IWorkflowRun, ITask } from '../lib/types';

export const projectApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    project: builder.query<ApiResponse<IProject>, string>({
      query: (projectId) => `/projects/${projectId}`,
      providesTags: (_result, _error, projectId) => [{ type: QueryTag.Project, id: projectId }],
    }),

    projectWorkflows: builder.query<ApiCollectionResponse<IWorkflow>, string>({
      query: (projectId) => `/projects/${projectId}/workflows`,
      providesTags: (result) => providesListTag(result?.data, QueryTag.Workflow),
    }),

    projectWorkflowRuns: builder.query<ApiCollectionResponse<IWorkflowRun>, string>({
      query: (projectId) => `/projects/${projectId}/workflow_runs`,
      providesTags: (result) => providesListTag(result?.data, QueryTag.WorkflowRun),
    }),

    projectArtifacts: builder.query<ApiCollectionResponse<IArtifact>, string>({
      query: (projectId) => `/projects/${projectId}/artifacts`,
      providesTags: (result) => providesListTag(result?.data, QueryTag.Artifact),
    }),

    projectTasks: builder.query<ApiCollectionResponse<ITask>, string>({
      query: (projectId) => `/projects/${projectId}/tasks`,
      providesTags: (result) => providesListTag(result?.data, QueryTag.Task),
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
