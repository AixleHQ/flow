# frozen_string_literal: true

module Api
  module V1
    module Projects
      module Board
        class TasksController < Board::ApplicationController
          # @summary List board tasks, filtered and paginated
          #
          # This is the board's per-column pagination endpoint: a column asks for
          # `board_column_id` + `limit`/`offset` and reads the column's unpaginated
          # total from the `X-Total-Count` response header, so it can show the real
          # count while holding only the pages it has scrolled to.
          def index
            scope = filtered_tasks
            response.set_header("X-Total-Count", scope.count.to_s)

            tasks = scope
              .includes(:assignee, :child_tasks, :task_comments, :task_assets, { workflow_runs: :workflow }, :pending_gates, :gates)
              .in_board_order
            tasks = tasks.limit(params[:limit]) if params[:limit].present?
            tasks = tasks.offset(params[:offset]) if params[:offset].present?
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
            if task.errors.empty?
              render json: BoardTaskResource.new(task).to_h
            else
              render json: { errors: task.errors.full_messages }, status: :unprocessable_entity
            end
          end

          def destroy
            task = current_board.board_tasks.find(params[:id])
            TaskService.destroy(task: task, actor: current_user)
            head :no_content
          end

          # @summary Move a board task to a column and position
          def move
            task = current_board.board_tasks.find(params[:id])
            target_column = current_board.board_columns.find(params[:column_id])
            moved_task = TaskService.move(task: task, to_column: target_column, position: params[:position]&.to_i, actor: current_user)
            render json: BoardTaskResource.new(moved_task).to_h
          end

          # @summary Archive a board task (drops it from the default board load)
          def archive
            task = current_board.board_tasks.find(params[:id])
            task = TaskService.archive(task: task, actor: current_user)
            render json: BoardTaskResource.new(task).to_h
          end

          # @summary Unarchive a board task (restores it to the default board load)
          def unarchive
            task = current_board.board_tasks.find(params[:id])
            task = TaskService.unarchive(task: task, actor: current_user)
            render json: BoardTaskResource.new(task).to_h
          end

          # @summary Apply a bulk action to multiple board tasks
          def bulk_actions
            action_type = params[:action_type]
            unless action_type.present?
              render json: { errors: [ "action_type is required" ] }, status: :bad_request and return
            end

            action = action_type.to_sym

            unless TaskService::BULK_ACTIONS.include?(action)
              render json: { errors: [ "Unknown action" ] }, status: :bad_request and return
            end

            task_ids = Array(params[:task_ids]).map(&:to_i)
            if task_ids.empty?
              render json: { errors: [ "task_ids is required" ] }, status: :bad_request and return
            end

            tasks = current_board.board_tasks.where(id: task_ids)

            to_column = case action
            when :move_to_column
              col_id = params[:column_id]
              unless col_id.present?
                render json: { errors: [ "column_id is required" ] }, status: :bad_request and return
              end
              col = current_board.board_columns.find_by(id: col_id)
              unless col
                render json: { errors: [ "Column not found" ] }, status: :not_found and return
              end
              col
            when :move_to_done
              done_col = current_board.board_columns.order(:position).last
              unless done_col
                render json: { errors: [ "Board has no Done column" ] }, status: :unprocessable_entity and return
              end
              done_col
            end

            result = TaskService.bulk_action(action: action, tasks: tasks, actor: current_user, to_column: to_column)
            render json: result
          end

          # @summary List workflow runs for a board task
          def workflow_runs
            task = current_board.board_tasks.find(params[:id])
            runs = task.workflow_runs.includes(:workflow, step_runs: :step).order(created_at: :desc)
            render json: runs.map { |r| TaskWorkflowRunResource.new(r).to_h }
          end

          # @summary Trigger the bound workflow for a board task
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

          # Every board filter, applied server-side. The board used to filter its
          # in-memory task array, which only worked while it held every task; a
          # paginated column has to ask the server instead.
          #
          # The plain attribute filters (title/assignee/type/priority) go through
          # ransack — `q[title_cont]`, `q[assignee_id_eq]`, … — against
          # BoardTask.ransackable_attributes. Column, tags and archived stay explicit
          # params: they are an existing contract, and neither array containment nor
          # the archived tri-state is a ransack predicate.
          def filtered_tasks
            scope = current_board.board_tasks
            scope = scope.where(board_column_id: params[:board_column_id]) if params[:board_column_id].present?
            scope = filter_by_tags(scope)
            filter_by_archived(scope).ransack(q_params).result
          end

          # `tags_match=all` narrows to tasks carrying *every* listed tag, which is what
          # the board's tag filter means. The default stays `any` (overlap) so existing
          # callers of this endpoint keep the behavior they were written against.
          def filter_by_tags(scope)
            tags = Array(params[:tags]).reject(&:blank?)
            return scope if tags.empty?

            params[:tags_match].to_s == "all" ? scope.tags_contains(tags) : scope.tags_overlap(tags)
          end

          # Default view hides archived tasks. `archived=archived` returns only archived
          # tasks (for the "Show archived" toggle); `archived=all` returns everything.
          def filter_by_archived(scope)
            case params[:archived].to_s
            when "archived" then scope.archived
            when "all" then scope
            else scope.active
            end
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
