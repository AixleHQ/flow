# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        module Board
          class TasksController < Api::V1::Company::Projects::ApplicationController
            def index
              tasks = current_board.board_tasks.ransack(q_params).result
              tasks = tasks.where(board_column_id: params[:board_column_id]) if params[:board_column_id].present?
              tasks = tasks.tags_overlap(Array(params[:tags])) if params[:tags].present?
              respond_with tasks, each_serializer: BoardTaskSerializer
            end

            def show
              task = current_board.board_tasks.find(params[:id])
              respond_with task, serializer: BoardTaskSerializer
            end

            def create
              task = current_board.board_tasks.build(task_params)
              if task.save
                ActivityRecorder.record(
                  board: current_board, event_type: :task_created, actor: current_user,
                  actor_type: :human, task: task,
                  metadata: { title: task.title, task_type: task.task_type }
                )
                WorkflowAutoTriggerService.check!(task: task, actor: current_user)
              end
              respond_with task, serializer: BoardTaskSerializer
            end

            def update
              task = current_board.board_tasks.find(params[:id])
              task.assign_attributes(task_params)
              changes = task.changes
              if task.save
                ActivityRecorder.record(
                  board: current_board, event_type: :task_updated, actor: current_user,
                  actor_type: :human, task: task,
                  metadata: { changes: changes.except("updated_at") }
                )
              end
              respond_with task, serializer: BoardTaskSerializer
            end

            def destroy
              task = current_board.board_tasks.find(params[:id])
              title = task.title
              if task.destroy
                ActivityRecorder.record(
                  board: current_board, event_type: :task_deleted, actor: current_user,
                  actor_type: :human, metadata: { title: title }
                )
              end
              respond_with task
            end

            def move
              task = current_board.board_tasks.find(params[:id])
              target_column = current_board.board_columns.find(params[:column_id])

              service = TaskMoveService.new(
                task: task,
                target_column: target_column,
                actor: current_user,
                position: params[:position]&.to_i
              )
              moved_task = service.execute

              respond_with moved_task, serializer: BoardTaskSerializer
            end

            def workflow_runs
              task = current_board.board_tasks.find(params[:id])
              runs = task.workflow_runs.order(created_at: :desc)
              respond_with runs, each_serializer: TaskWorkflowRunSerializer
            end

            def trigger_workflow
              task = current_board.board_tasks.find(params[:id])
              binding = task.board_column.column_workflow_binding

              unless binding&.trigger_mode&.to_sym == :manual
                return render json: { errors: [ "No manual workflow binding on current column" ] }, status: :unprocessable_entity
              end

              if task.workflow_runs.where(state: %w[pending running paused]).exists?
                return render json: { errors: [ "Active workflow run already exists for this task" ] }, status: :unprocessable_entity
              end

              run = WorkflowRun.create!(
                workflow: binding.workflow,
                project: current_project,
                user: current_user,
                board_task_id: task.id,
                mode: :non_interactive
              )

              WorkflowService.start_workflow_execution(run)

              respond_with run
            end

            private

            def current_board
              @current_board ||= current_project.board || raise(ActiveRecord::RecordNotFound)
            end

            def task_params
              params.require(:board_task).permit(
                :title, :description, :task_type, :priority,
                :assignee_id, :board_column_id, :parent_task_id,
                tags: []
              )
            end
          end
        end
      end
    end
  end
end
