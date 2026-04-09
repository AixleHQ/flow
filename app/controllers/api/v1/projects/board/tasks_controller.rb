# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Board
        class TasksController < Board::ApplicationController
          def index
            tasks = current_board.board_tasks
                                 .includes(:assignee, :child_tasks, :task_comments, :task_assets, { workflow_runs: :workflow }, :pending_task_waits)
            tasks = tasks.where(board_column_id: params[:board_column_id]) if params[:board_column_id].present?
            tasks = tasks.tags_overlap(Array(params[:tags])) if params[:tags].present?
            render json: tasks.map { |t| BoardTaskResource.new(t).to_h }
          end

          def show
            task = current_board.board_tasks.find(params[:id])
            render json: BoardTaskResource.new(task).to_h
          end

          def create
            task = TaskService.create(board: current_board, params: task_params, actor: current_user)
            if task.persisted?
              render json: BoardTaskResource.new(task).to_h, status: :created
            else
              render json: { errors: task.errors.full_messages }, status: :unprocessable_entity
            end
          end

          def update
            task = current_board.board_tasks.find(params[:id])
            task = TaskService.update(task: task, params: task_params, actor: current_user)
            render json: BoardTaskResource.new(task).to_h
          end

          def destroy
            task = current_board.board_tasks.find(params[:id])
            TaskService.destroy(task: task, actor: current_user)
            head :no_content
          end

          def move
            task = current_board.board_tasks.find(params[:id])
            target_column = current_board.board_columns.find(params[:column_id])
            moved_task = TaskService.move(task: task, to_column: target_column, position: params[:position]&.to_i, actor: current_user)
            render json: BoardTaskResource.new(moved_task).to_h
          end

          def workflow_runs
            task = current_board.board_tasks.find(params[:id])
            runs = task.workflow_runs.includes(:workflow).order(created_at: :desc)
            render json: runs.map { |r| TaskWorkflowRunResource.new(r).to_h }
          end

          def trigger_workflow
            task = current_board.board_tasks.find(params[:id])
            binding = task.board_column.column_workflow_binding
            result = TaskService.trigger_workflow(task: task, binding: binding, actor: current_user)

            if result.is_a?(Hash) && result[:error]
              render json: { errors: [ result[:error] ] }, status: :unprocessable_entity
            else
              render json: WorkflowRunResource.new(result).to_h
            end
          end

          private

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
