import type {
  Board,
  BoardActivity,
  BoardColumn,
  BoardTask,
  PaginatedResponse,
  TaskAsset,
  TaskComment,
  TaskWorkflowRun,
} from 'entities/board-task';
import { baseApi, QueryTag } from 'shared/api';

interface BoardWithTasks {
  board: Board;
  tasks: BoardTask[];
}

interface ProjectMember {
  id: number;
  email: string;
  name: string;
  role: string;
}

const boardBasePath = (projectId: number) => `/api/v1/company/projects/${projectId}/board`;
const tasksBasePath = (projectId: number) => `${boardBasePath(projectId)}/tasks`;
const columnsBasePath = (projectId: number) => `${boardBasePath(projectId)}/columns`;

interface BoardPreset {
  key: string;
  displayName: string;
  columns: string[];
}

export const boardApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getBoardPresets: builder.query<BoardPreset[], number>({
      query: (projectId) => ({
        url: `${boardBasePath(projectId)}/presets`,
        method: 'GET',
      }),
    }),

    createBoard: builder.mutation<Board, { projectId: number; preset?: string; name?: string }>({
      query: ({ projectId, preset, name }) => ({
        url: boardBasePath(projectId),
        method: 'POST',
        data: { board: { preset, name } },
      }),
      transformResponse: (response: { data: Board }) => response.data,
      invalidatesTags: [QueryTag.Task],
    }),

    getProjectMembers: builder.query<{ items: ProjectMember[] }, number>({
      query: (projectId) => ({
        url: `/api/v1/company/projects/${projectId}/collaborators`,
        method: 'GET',
      }),
    }),

    getBoard: builder.query<BoardWithTasks, number>({
      async queryFn(projectId, _api, _extraOptions, baseQuery) {
        const boardResult = await baseQuery({ url: boardBasePath(projectId), method: 'GET' });
        if (boardResult.error) return { error: boardResult.error };

        const tasksResult = await baseQuery({ url: tasksBasePath(projectId), method: 'GET' });
        if (tasksResult.error) return { error: tasksResult.error };

        const boardData = boardResult.data as { data: Board };
        const tasksData = tasksResult.data as { items: BoardTask[] };

        return {
          data: {
            board: boardData.data,
            tasks: tasksData.items || [],
          },
        };
      },
      providesTags: [QueryTag.Task],
    }),

    createTask: builder.mutation<BoardTask, { projectId: number; boardTask: Partial<BoardTask> }>({
      query: ({ projectId, boardTask }) => ({
        url: tasksBasePath(projectId),
        method: 'POST',
        data: { boardTask },
      }),
      transformResponse: (response: { data: BoardTask }) => response.data,
      invalidatesTags: [QueryTag.Task],
    }),

    updateTask: builder.mutation<BoardTask, { projectId: number; taskId: number; boardTask: Partial<BoardTask> }>({
      query: ({ projectId, taskId, boardTask }) => ({
        url: `${tasksBasePath(projectId)}/${taskId}`,
        method: 'PATCH',
        data: { boardTask },
      }),
      transformResponse: (response: { data: BoardTask }) => response.data,
      invalidatesTags: [QueryTag.Task],
    }),

    deleteTask: builder.mutation<void, { projectId: number; taskId: number }>({
      query: ({ projectId, taskId }) => ({
        url: `${tasksBasePath(projectId)}/${taskId}`,
        method: 'DELETE',
      }),
      invalidatesTags: [QueryTag.Task],
    }),

    moveTask: builder.mutation<BoardTask, { projectId: number; taskId: number; columnId: number; position?: number }>({
      query: ({ projectId, taskId, columnId, position }) => ({
        url: `${tasksBasePath(projectId)}/${taskId}/move`,
        method: 'PATCH',
        data: { columnId, position },
      }),
      transformResponse: (response: { data: BoardTask }) => response.data,
      async onQueryStarted({ projectId, taskId, columnId, position }, { dispatch, queryFulfilled }) {
        const patchResult = dispatch(
          boardApi.util.updateQueryData('getBoard', projectId, (draft) => {
            const task = draft.tasks.find((t) => t.id === taskId);
            if (!task) return;

            const oldColumnId = task.boardColumnId;
            const oldPosition = task.position;
            const sameColumn = oldColumnId === columnId;

            if (position !== undefined) {
              if (sameColumn) {
                for (const t of draft.tasks) {
                  if (t.id === taskId || t.boardColumnId !== columnId) continue;
                  if (oldPosition < position) {
                    if (t.position > oldPosition && t.position <= position) t.position -= 1;
                  } else if (oldPosition > position) {
                    if (t.position >= position && t.position < oldPosition) t.position += 1;
                  }
                }
              } else {
                for (const t of draft.tasks) {
                  if (t.id === taskId) continue;
                  if (t.boardColumnId === columnId && t.position >= position) t.position += 1;
                }
              }
            }

            task.boardColumnId = columnId;
            if (position !== undefined) task.position = position;
          }),
        );
        try {
          await queryFulfilled;
        } catch {
          patchResult.undo();
        }
      },
    }),

    getTaskComments: builder.query<
      TaskComment[],
      { projectId: number; taskId: number; tag?: string; authorType?: string }
    >({
      query: ({ projectId, taskId, tag, authorType }) => ({
        url: `${tasksBasePath(projectId)}/${taskId}/comments`,
        method: 'GET',
        params: {
          ...(tag && { 'q[with_tag]': tag }),
          ...(authorType && { 'q[by_author_type]': authorType }),
        },
        isDecamelize: false,
      }),
      transformResponse: (response: { items: TaskComment[] }) => response.items || [],
      providesTags: [QueryTag.Comment],
    }),

    createComment: builder.mutation<TaskComment, { projectId: number; taskId: number; body: string; tags?: string[] }>({
      query: ({ projectId, taskId, body, tags }) => ({
        url: `${tasksBasePath(projectId)}/${taskId}/comments`,
        method: 'POST',
        data: { taskComment: { body, tags: tags || [] } },
      }),
      transformResponse: (response: { data: TaskComment }) => response.data,
      invalidatesTags: [QueryTag.Comment, QueryTag.Task],
    }),

    getTaskAssets: builder.query<TaskAsset[], { projectId: number; taskId: number; tag?: string }>({
      query: ({ projectId, taskId, tag }) => ({
        url: `${tasksBasePath(projectId)}/${taskId}/assets`,
        method: 'GET',
        params: tag ? { tag } : undefined,
      }),
      transformResponse: (response: { items: TaskAsset[] }) => response.items || [],
      providesTags: [QueryTag.TaskAsset],
    }),

    createAsset: builder.mutation<TaskAsset, { projectId: number; taskId: number; formData: FormData }>({
      query: ({ projectId, taskId, formData }) => ({
        url: `${tasksBasePath(projectId)}/${taskId}/assets`,
        method: 'POST',
        data: formData,
        isDecamelize: false,
      }),
      transformResponse: (response: { data: TaskAsset }) => response.data,
      invalidatesTags: [QueryTag.TaskAsset, QueryTag.Task],
    }),

    triggerWorkflow: builder.mutation<unknown, { projectId: number; taskId: number }>({
      query: ({ projectId, taskId }) => ({
        url: `${tasksBasePath(projectId)}/${taskId}/trigger_workflow`,
        method: 'POST',
      }),
      invalidatesTags: [QueryTag.Task, QueryTag.WorkflowRun],
    }),

    getTaskWorkflowRuns: builder.query<TaskWorkflowRun[], { projectId: number; taskId: number }>({
      query: ({ projectId, taskId }) => ({
        url: `${tasksBasePath(projectId)}/${taskId}/workflow_runs`,
        method: 'GET',
      }),
      transformResponse: (response: { items: TaskWorkflowRun[] }) => response.items || [],
      providesTags: [QueryTag.WorkflowRun],
    }),

    getBoardActivities: builder.query<
      PaginatedResponse<BoardActivity>,
      { projectId: number; page?: number; perPage?: number; eventType?: string; actorType?: string; since?: string }
    >({
      query: ({ projectId, page, perPage, eventType, actorType, since }) => ({
        url: `${boardBasePath(projectId)}/activities`,
        method: 'GET',
        params: {
          ...(page && { page }),
          ...(perPage && { per_page: perPage }),
          ...(eventType && { event_type: eventType }),
          ...(actorType && { actor_type: actorType }),
          ...(since && { since }),
        },
        isDecamelize: false,
      }),
      providesTags: [QueryTag.Activity],
    }),

    getTaskActivities: builder.query<
      PaginatedResponse<BoardActivity>,
      { projectId: number; taskId: number; page?: number; perPage?: number }
    >({
      query: ({ projectId, taskId, page, perPage }) => ({
        url: `${tasksBasePath(projectId)}/${taskId}/activities`,
        method: 'GET',
        params: { ...(page && { page }), ...(perPage && { per_page: perPage }) },
        isDecamelize: false,
      }),
      providesTags: [QueryTag.Activity],
    }),

    getViewPresets: builder.query<
      Array<{ id: number; name: string; filters: Record<string, unknown>; userId: number; shared: boolean }>,
      number
    >({
      query: (projectId) => ({
        url: `${boardBasePath(projectId)}/view_presets`,
        method: 'GET',
      }),
      transformResponse: (response: {
        items: Array<{ id: number; name: string; filters: Record<string, unknown>; userId: number; shared: boolean }>;
      }) => response.items || [],
      providesTags: [QueryTag.ViewPreset],
    }),

    createViewPreset: builder.mutation<
      unknown,
      { projectId: number; boardViewPreset: { name: string; shared: boolean; filters: Record<string, unknown> } }
    >({
      query: ({ projectId, boardViewPreset }) => ({
        url: `${boardBasePath(projectId)}/view_presets`,
        method: 'POST',
        data: { boardViewPreset },
      }),
      invalidatesTags: [QueryTag.ViewPreset],
    }),

    deleteViewPreset: builder.mutation<void, { projectId: number; presetId: number }>({
      query: ({ projectId, presetId }) => ({
        url: `${boardBasePath(projectId)}/view_presets/${presetId}`,
        method: 'DELETE',
      }),
      invalidatesTags: [QueryTag.ViewPreset],
    }),

    createColumn: builder.mutation<BoardColumn, { projectId: number; boardColumn: { name: string; purpose?: string } }>(
      {
        query: ({ projectId, boardColumn }) => ({
          url: columnsBasePath(projectId),
          method: 'POST',
          data: { boardColumn },
        }),
        invalidatesTags: [QueryTag.Task],
      },
    ),

    updateColumn: builder.mutation<
      BoardColumn,
      { projectId: number; id: number; boardColumn: { name?: string; purpose?: string } }
    >({
      query: ({ projectId, id, boardColumn }) => ({
        url: `${columnsBasePath(projectId)}/${id}`,
        method: 'PATCH',
        data: { boardColumn },
      }),
      invalidatesTags: [QueryTag.Task],
    }),

    deleteColumn: builder.mutation<void, { projectId: number; id: number }>({
      query: ({ projectId, id }) => ({
        url: `${columnsBasePath(projectId)}/${id}`,
        method: 'DELETE',
      }),
      invalidatesTags: [QueryTag.Task],
    }),

    reorderColumns: builder.mutation<BoardColumn[], { projectId: number; columnIds: number[] }>({
      query: ({ projectId, columnIds }) => ({
        url: `${columnsBasePath(projectId)}/reorder`,
        method: 'PATCH',
        data: { columnIds },
      }),
      invalidatesTags: [QueryTag.Task],
    }),

    createWorkflowBinding: builder.mutation<
      unknown,
      { projectId: number; columnId: number; workflowId: number; triggerMode: string; cooldownSeconds?: number }
    >({
      query: ({ projectId, columnId, workflowId, triggerMode, cooldownSeconds }) => ({
        url: `${columnsBasePath(projectId)}/${columnId}/workflow_binding`,
        method: 'POST',
        data: { columnWorkflowBinding: { workflowId, triggerMode, cooldownSeconds: cooldownSeconds ?? 0 } },
      }),
      invalidatesTags: [QueryTag.Task],
    }),

    updateWorkflowBinding: builder.mutation<
      unknown,
      { projectId: number; columnId: number; workflowId?: number; triggerMode?: string; cooldownSeconds?: number }
    >({
      query: ({ projectId, columnId, ...data }) => ({
        url: `${columnsBasePath(projectId)}/${columnId}/workflow_binding`,
        method: 'PATCH',
        data: { columnWorkflowBinding: data },
      }),
      invalidatesTags: [QueryTag.Task],
    }),

    deleteWorkflowBinding: builder.mutation<void, { projectId: number; columnId: number }>({
      query: ({ projectId, columnId }) => ({
        url: `${columnsBasePath(projectId)}/${columnId}/workflow_binding`,
        method: 'DELETE',
      }),
      invalidatesTags: [QueryTag.Task],
    }),

    deleteAsset: builder.mutation<void, { projectId: number; taskId: number; assetId: number }>({
      query: ({ projectId, taskId, assetId }) => ({
        url: `${tasksBasePath(projectId)}/${taskId}/assets/${assetId}`,
        method: 'DELETE',
      }),
      invalidatesTags: [QueryTag.TaskAsset, QueryTag.Task],
    }),

    getTaskDetails: builder.query<BoardTask, { projectId: number; taskId: number }>({
      query: ({ projectId, taskId }) => ({
        url: `${tasksBasePath(projectId)}/${taskId}`,
        method: 'GET',
      }),
      transformResponse: (response: { data: BoardTask }) => response.data,
      providesTags: [QueryTag.Task],
    }),
  }),
});

export const {
  useGetBoardPresetsQuery,
  useCreateBoardMutation,
  useGetProjectMembersQuery,
  useGetBoardQuery,
  useCreateTaskMutation,
  useUpdateTaskMutation,
  useDeleteTaskMutation,
  useMoveTaskMutation,
  useTriggerWorkflowMutation,
  useGetTaskWorkflowRunsQuery,
  useGetBoardActivitiesQuery,
  useGetTaskActivitiesQuery,
  useGetTaskCommentsQuery,
  useCreateCommentMutation,
  useGetTaskAssetsQuery,
  useCreateAssetMutation,
  useDeleteAssetMutation,
  useGetViewPresetsQuery,
  useCreateViewPresetMutation,
  useDeleteViewPresetMutation,
  useCreateColumnMutation,
  useUpdateColumnMutation,
  useDeleteColumnMutation,
  useReorderColumnsMutation,
  useCreateWorkflowBindingMutation,
  useUpdateWorkflowBindingMutation,
  useDeleteWorkflowBindingMutation,
  useGetTaskDetailsQuery,
} = boardApi;
