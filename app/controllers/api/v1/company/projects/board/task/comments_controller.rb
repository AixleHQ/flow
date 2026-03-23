# frozen_string_literal: true

module Api
  module V1
    module Company
      module Projects
        module Board
          module Task
            class CommentsController < Api::V1::Company::Projects::ApplicationController
              def index
                comments = current_task.task_comments.includes(:author).ransack(params[:q]).result.order(created_at: :desc)
                respond_with comments, each_serializer: TaskCommentSerializer
              end

              def create
                comment = TaskService.add_comment(
                  task: current_task,
                  params: comment_params,
                  actor: current_user
                )
                respond_with comment, serializer: TaskCommentSerializer
              end

              private

              def current_board
                @current_board ||= current_project.board || raise(ActiveRecord::RecordNotFound)
              end

              def current_task
                @current_task ||= current_board.board_tasks.find(params[:task_id])
              end

              def comment_params
                params.require(:task_comment).permit(:body, tags: [])
              end
            end
          end
        end
      end
    end
  end
end
