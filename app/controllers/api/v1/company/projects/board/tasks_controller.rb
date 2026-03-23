# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        module Board
          class TasksController < Api::V1::Company::Projects::ApplicationController
            def index
              tasks = current_board.board_tasks
                                   .includes(:assignee, :child_tasks, :task_comments, :task_assets, :workflow_runs, :task_waits)
                                   .ransack(q_params).result
              tasks = tasks.where(board_column_id: params[:board_column_id]) if params[:board_column_id].present?
              tasks = tasks.tags_overlap(Array(params[:tags])) if params[:tags].present?
              respond_with tasks, each_serializer: BoardTaskSerializer
            end

            def show
              task = current_board.board_tasks.find(params[:id])
              respond_with task, serializer: BoardTaskSerializer
            end

            def create
              task = TaskService.create(board: current_board, params: task_params, actor: current_user)
              respond_with task, serializer: BoardTaskSerializer
            end

            def update
              task = current_board.board_tasks.find(params[:id])
              task = TaskService.update(task: task, params: task_params, actor: current_user)
              respond_with task, serializer: BoardTaskSerializer
            end

            def destroy
              task = current_board.board_tasks.find(params[:id])
              TaskService.destroy(task: task, actor: current_user)
              respond_with task
            end

            def move
              task = current_board.board_tasks.find(params[:id])
              target_column = current_board.board_columns.find(params[:column_id])

              moved_task = TaskService.move(
                task: task,
                to_column: target_column,
                position: params[:position]&.to_i,
                actor: current_user
              )

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

              result = TaskService.trigger_workflow(task: task, binding: binding, actor: current_user)

              if result.is_a?(Hash) && result[:error]
                render json: { errors: [ result[:error] ] }, status: :unprocessable_entity
              else
                respond_with result
              end
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
