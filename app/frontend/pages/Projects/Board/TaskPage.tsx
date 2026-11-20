import { Head, Link, router, usePage } from '@inertiajs/react';
import { Anchor, Badge, Group } from '@mantine/core';
import { IconArrowLeft } from '@tabler/icons-react';
import { useCallback, useMemo } from 'react';

import type BoardActivity from 'types/generated/BoardActivity';
import type BoardMember from 'types/generated/BoardMember';
import type Project from 'types/generated/Project';
import type TaskAsset from 'types/generated/TaskAsset';
import type TaskComment from 'types/generated/TaskComment';
import type TaskDetail from 'types/generated/TaskDetail';
import type TaskStatistics from 'types/generated/TaskStatistics';
import type TaskWorkflowRun from 'types/generated/TaskWorkflowRun';

import { apiMutate } from 'shared/lib/apiFetch';
import { useInertiaCableStream } from 'shared/lib/hooks/useInertiaCableStream';
import { useProjectPermissions } from 'shared/lib/hooks/useProjectPermissions';
import { apiV1ProjectTaskPath, companyProjectBoardPath, companyProjectTaskPath } from 'shared/routes';

import { persistentProjectLayout, setPageLayout } from '../ProjectLayout';

import type { BoardTeam } from './assignee';
import styles from './BoardPage.module.css';
import { normalizeTask } from './normalizeTask';
import { TaskDetailSidebar } from './TaskDetailSidebar';
import type { Column, Task } from './types';

interface Props {
  project: Project;
  selectedTask: TaskDetail;
  columns: Column[];
  boardTags?: string[];
  epics?: Array<{ id: number; number: number; title: string }>;
  members: BoardMember[];
  teams?: BoardTeam[];
  currentUserId?: number;
  taskCableStream?: string | null;
  taskComments?: TaskComment[];
  taskAssets?: TaskAsset[];
  taskActivities?: BoardActivity[];
  taskWorkflowRuns?: TaskWorkflowRun[];
  taskStatistics?: TaskStatistics | null;
  [key: string]: unknown;
}

const NO_TASKS: Task[] = [];
const NO_EPICS: Array<{ id: number; number: number; title: string }> = [];
const NO_TEAMS: BoardTeam[] = [];

const TaskPage = () => {
  const {
    project,
    selectedTask,
    columns,
    boardTags,
    epics,
    members,
    teams = NO_TEAMS,
    currentUserId,
    taskCableStream,
    taskComments,
    taskAssets,
    taskActivities,
    taskWorkflowRuns,
    taskStatistics,
  } = usePage<Props>().props;
  const { canExecute } = useProjectPermissions();
  const boardPath = companyProjectBoardPath(project.id);

  useInertiaCableStream(taskCableStream ?? undefined, {
    only: ['selected_task', 'task_comments', 'task_assets', 'task_activities', 'task_workflow_runs', 'task_statistics'],
  });

  const task = useMemo(() => normalizeTask(selectedTask), [selectedTask]);
  const knownTags = useMemo(() => [...(boardTags ?? [])].sort(), [boardTags]);

  const deleteTask = useCallback(
    async (taskId: number) => {
      if (await apiMutate(apiV1ProjectTaskPath(project.id, taskId), { method: 'DELETE' })) router.visit(boardPath);
    },
    [project.id, boardPath],
  );

  const openTaskNumber = useCallback(
    (taskNumber: number) => router.visit(companyProjectTaskPath(project.id, taskNumber)),
    [project.id],
  );

  return (
    <>
      <Head title={`#${task.number} ${task.title} — ${project.name}`} />
      <Group gap="sm" mb="sm">
        <Anchor component={Link} href={boardPath} size="sm" c="dimmed" className={styles.taskPageBack}>
          <IconArrowLeft size={14} /> Tasks
        </Anchor>
        {task.archived && (
          <Badge variant="light" color="gray" size="sm">
            Archived
          </Badge>
        )}
      </Group>
      <TaskDetailSidebar
        variant="page"
        task={task}
        pendingTaskNumber={null}
        allTasks={NO_TASKS}
        epics={epics ?? NO_EPICS}
        knownTags={knownTags}
        onDelete={deleteTask}
        onOpenTaskNumber={openTaskNumber}
        projectId={project.id}
        columns={columns}
        members={members}
        teams={teams}
        comments={taskComments ?? []}
        activities={taskActivities ?? []}
        taskAssets={taskAssets ?? []}
        workflowRuns={taskWorkflowRuns ?? []}
        stats={taskStatistics ?? null}
        canExecute={canExecute}
        currentUserId={currentUserId ?? 0}
      />
    </>
  );
};

setPageLayout(TaskPage, persistentProjectLayout);

export default TaskPage;
